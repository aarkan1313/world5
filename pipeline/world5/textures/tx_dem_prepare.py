"""tx_dem_prepare — prepare a raw DEM for a world bundle.

Spec 19 §"DEM source handling defined upfront". Sprint 2 of the DEM
runtime-kernels epic.

Takes a raw DEM (GeoTIFF in any CRS, any extent) + bundle-author-
specified world bounds, and produces:
1. A cropped + reprojected GeoTIFF at `<bundle>/dem/<id>.tif` in a
   bundle-specified target CRS.
2. A sidecar JSON matching dem_source.schema.json with the actual
   elevation range, computed bounds, resolution.

Sprint 2 v1: single-tile output. Sprint 4 extends to a tile pyramid
for infinite-world streaming.

Usage:
    python -m world5.textures.tx_dem_prepare \\
        --bundle engine/worlds/walking_demo \\
        --source d:/assets/world3/opentopo/processed/.../cop30/dem.tif \\
        --id cascades_excerpt \\
        --bounds-world-xz -2048 -2048 2048 2048 \\
        --crs EPSG:32610 \\
        --attribution "Copernicus GLO-30 (CC BY 4.0)"

After running, edit the bundle's biome_catalog.json to add a
dem_feature stage referencing the id, and the runtime will pick it up.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def prepare_dem(
    source_path: Path,
    bundle_root: Path,
    dem_id: str,
    bounds_world_xz: tuple[float, float, float, float],
    target_crs: str,
    attribution: str = "",
) -> dict:
    """Reproject + crop source DEM into bundle. Returns the sidecar dict."""
    try:
        import rasterio  # type: ignore
        from rasterio.warp import calculate_default_transform, reproject, Resampling  # type: ignore
    except ImportError as e:
        raise ImportError(
            "rasterio required for DEM preparation; install via pip"
        ) from e

    if not source_path.exists():
        raise FileNotFoundError(f"source DEM not found: {source_path}")
    dem_dir = bundle_root / "dem"
    dem_dir.mkdir(parents=True, exist_ok=True)
    out_path = dem_dir / f"{dem_id}.tif"
    sidecar_path = dem_dir / f"{dem_id}.json"

    min_x, min_z, max_x, max_z = bounds_world_xz
    if min_x >= max_x or min_z >= max_z:
        raise ValueError(
            f"invalid bounds_world_xz: min must be < max "
            f"(got [{min_x}, {min_z}, {max_x}, {max_z}])"
        )

    with rasterio.open(source_path) as src:
        src_crs = src.crs.to_string() if src.crs else "unknown"
        print(f"  source CRS: {src_crs}")
        print(f"  source size: {src.width}x{src.height}")
        # Target window in target CRS.
        target_transform, target_width, target_height = (
            calculate_default_transform(
                src.crs, target_crs, src.width, src.height,
                *src.bounds
            )
        )
        # Override transform to cover ONLY the requested world-XZ window.
        # We want the output to span [min_x, min_z, max_x, max_z] in
        # target_crs coordinates. Choose pixel size so output has a
        # sensible resolution matching the source (preserve detail).
        # Source res in target CRS: approximate via source bounds size.
        src_res_x = (src.bounds.right - src.bounds.left) / src.width
        src_res_y = (src.bounds.top - src.bounds.bottom) / src.height
        # Use the finer of the two.
        cell_size = min(src_res_x, src_res_y)
        out_width = max(1, int((max_x - min_x) / cell_size))
        out_height = max(1, int((max_z - min_z) / cell_size))
        # Cap at 1024 in either dim for v1 RAM-load runtime path
        # (Sprint 3). Sprint 4 adds tile-pyramid output for higher
        # resolution without RAM blowup. 1024² @ float32 = 4 MB; at
        # 4 km world = ~4 m/cell, which is finer than the typical
        # heightmap page sampling.
        if out_width > 1024 or out_height > 1024:
            scale = max(out_width, out_height) / 1024.0
            out_width = max(1, int(out_width / scale))
            out_height = max(1, int(out_height / scale))
        # Affine transform: top-left at (min_x, max_z); pixel size + flip Y.
        from rasterio.transform import from_origin
        target_transform = from_origin(
            min_x, max_z,
            (max_x - min_x) / out_width,
            (max_z - min_z) / out_height,
        )
        print(f"  output size: {out_width}x{out_height}")
        print(f"  output cell: ~{(max_x - min_x) / out_width:.2f}m")

        meta = src.meta.copy()
        meta.update({
            "crs": target_crs,
            "transform": target_transform,
            "width": out_width,
            "height": out_height,
            "compress": "lzw",
        })

        with rasterio.open(out_path, "w", **meta) as dst:
            reproject(
                source=rasterio.band(src, 1),
                destination=rasterio.band(dst, 1),
                src_transform=src.transform,
                src_crs=src.crs,
                dst_transform=target_transform,
                dst_crs=target_crs,
                resampling=Resampling.bilinear,
            )

    # Compute elevation range from the prepared output (ignoring any
    # nodata sentinels rasterio inherited from the source).
    with rasterio.open(out_path) as out_src:
        arr = out_src.read(1).astype("float64")
        nodata = out_src.nodata
    if nodata is not None:
        valid_mask = arr != nodata
    else:
        # Heuristic: GeoTIFFs often use -9999 as fill even when nodata
        # isn't formally declared.
        valid_mask = arr > -9000
    if not valid_mask.any():
        raise ValueError(
            "prepared DEM has no valid pixels — check that "
            "bounds_world_xz overlaps the source raster in target CRS"
        )
    valid = arr[valid_mask]
    elev_min = float(valid.min())
    elev_max = float(valid.max())

    # Companion PNG for Godot runtime (Image can't read GeoTIFF).
    # 16-bit single-channel; normalized [0, 1] over elevation_range_m.
    # DemSource.gd decodes by rescaling pixel value × span + min.
    # PNG axis convention: row 0 = top = max_z, last row = min_z;
    # we WRITE with that orientation (matches GeoTIFF reading order).
    png_path = dem_dir / f"{dem_id}.png"
    import numpy as np
    from PIL import Image as PILImage
    span = max(elev_max - elev_min, 1e-6)
    norm = np.clip((arr - elev_min) / span, 0.0, 1.0)
    # Map invalid pixels to 0 so they read as min_elevation (better
    # than garbage; pipeline should crop to valid extent anyway).
    norm = np.where(valid_mask, norm, 0.0)
    norm_u16 = (norm * 65535.0).astype(np.uint16)
    PILImage.fromarray(norm_u16, mode="I;16").save(png_path, optimize=True)
    print(f"  -> {png_path} (16-bit PNG)")

    # Bake DEM features (ridge_emphasis / drainage_accumulation /
    # slope_deg / aspect_deg) into companion PNGs the GDScript runtime
    # can load directly. This keeps Python out of the runtime path —
    # the bundle just ships the feature PNGs alongside the height PNG.
    # Each feature is a 16-bit single-channel PNG, normalized [0, 1]
    # over the feature's value range (sidecar carries the rescale info).
    from world5.kernels import DemFeatureKernel
    # Load the prepared elevation grid as a 2D numpy array for the
    # kernel. Use the height PNG's normalized [0,1] values rescaled
    # back to world meters so the kernel operates on real-meter heights.
    norm_h = norm_u16.astype(np.float32) / 65535.0
    h_world_m = elev_min + norm_h * span
    feature_modes = ("ridge_emphasis", "drainage_accumulation", "slope_deg", "aspect_deg")
    kernel = DemFeatureKernel(modes=feature_modes)
    # Use full-size DEM grid (no extra resampling — features are at the
    # same resolution as the height PNG).
    feat_grid_n = max(h_world_m.shape[0], h_world_m.shape[1])
    print(f"  baking {len(feature_modes)} features at {feat_grid_n}²...")
    feat_result = kernel.extract(
        (bounds_world_xz[0], bounds_world_xz[1]),
        (bounds_world_xz[2], bounds_world_xz[3]),
        feat_grid_n,
        dem_array=h_world_m,
    )
    feature_paths: dict[str, str] = {}
    feature_ranges: dict[str, list[float]] = {}
    for mode, arr in feat_result.features.items():
        # All output modes are non-negative floats by design
        # (ridge_emphasis ∈ [0,1], drainage ∈ [0,1], slope ∈ [0,90],
        #  aspect ∈ [0,360)). Normalize per-feature for max PNG dynamic
        # range; sidecar carries the [min, max] so the runtime can
        # decode.
        f_min = float(arr.min())
        f_max = float(arr.max())
        f_span = max(f_max - f_min, 1e-6)
        norm_feat = np.clip((arr - f_min) / f_span, 0.0, 1.0)
        norm_feat_u16 = (norm_feat * 65535.0).astype(np.uint16)
        feat_png_path = dem_dir / f"{dem_id}_{mode}.png"
        PILImage.fromarray(norm_feat_u16, mode="I;16").save(
            feat_png_path, optimize=True)
        feature_paths[mode] = f"dem/{dem_id}_{mode}.png"
        feature_ranges[mode] = [f_min, f_max]
        print(f"    {mode}: range [{f_min:.3f}, {f_max:.3f}] -> {feat_png_path.name}")

    sidecar = {
        "_schema_version": 1,
        "id": dem_id,
        "path": f"dem/{dem_id}.tif",
        "png_path": f"dem/{dem_id}.png",
        "crs": target_crs,
        "bounds_world_xz": list(bounds_world_xz),
        "elevation_range_m": [elev_min, elev_max],
        "source_resolution_m": float(cell_size),
        "features": {
            "paths": feature_paths,
            "ranges": feature_ranges,
        },
    }
    if attribution:
        sidecar["attribution"] = attribution
    sidecar_path.write_text(
        json.dumps(sidecar, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"  -> {out_path}")
    print(f"  -> {sidecar_path}")
    print(f"  elevation: {elev_min:.1f}..{elev_max:.1f} m")
    return sidecar


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--bundle", type=Path, required=True,
                    help="world bundle root (e.g. engine/worlds/walking_demo)")
    ap.add_argument("--source", type=Path, required=True,
                    help="source DEM GeoTIFF (any CRS, any extent)")
    ap.add_argument("--id", required=True,
                    help="bundle-local DEM source ID (lowercase + underscores)")
    ap.add_argument("--bounds-world-xz", type=float, nargs=4,
                    metavar=("MIN_X", "MIN_Z", "MAX_X", "MAX_Z"),
                    default=None,
                    help="world-XZ bounds in meters (target CRS units). "
                         "If omitted, --auto-bounds-extent-m must be set to "
                         "derive bounds centered on the source DEM.")
    ap.add_argument("--auto-bounds-extent-m", type=float, default=None,
                    help="If set, ignore --bounds-world-xz; reproject the "
                         "source extent into target_crs, take the center, "
                         "and produce a square world centered on it with "
                         "this side length in meters. Easier UX when the "
                         "author just wants 'a 4 km patch from this DEM'.")
    ap.add_argument("--crs", default="EPSG:32610",
                    help="target CRS (default: EPSG:32610 / UTM zone 10N)")
    ap.add_argument("--attribution", default="",
                    help="license + attribution string for downstream display")
    args = ap.parse_args(argv)

    if not args.bundle.exists():
        print(f"bundle not found: {args.bundle}", file=sys.stderr)
        return 1
    if args.bounds_world_xz is None and args.auto_bounds_extent_m is None:
        print("error: must pass --bounds-world-xz OR --auto-bounds-extent-m",
              file=sys.stderr)
        return 1

    # Derive bounds from source if --auto-bounds-extent-m set.
    # Output bounds are centered on the WORLD origin (0, 0) — the
    # reproject step still pulls source pixels via the geographic
    # center, but the bundle's world-XZ sees the DEM as a (-half,
    # +half) square. This matches walking_demo + most W5 worlds
    # that center their origin on the player spawn.
    if args.auto_bounds_extent_m is not None:
        try:
            import rasterio  # type: ignore
            from rasterio.warp import transform_bounds  # type: ignore
        except ImportError:
            print("rasterio required for --auto-bounds-extent-m", file=sys.stderr)
            return 1
        with rasterio.open(args.source) as src:
            # Source extent in target CRS
            left, bottom, right, top = transform_bounds(
                src.crs, args.crs, *src.bounds
            )
        cx = (left + right) * 0.5
        cy = (bottom + top) * 0.5
        half = args.auto_bounds_extent_m * 0.5
        # Geographic bounds (used for the reproject pull)
        geo_bounds = (cx - half, cy - half, cx + half, cy + half)
        # World-XZ bounds we ADVERTISE to the runtime (centered on 0,0)
        bounds = (-half, -half, half, half)
        print(f"  geographic bounds (reproject pull): {geo_bounds}")
        print(f"  world-XZ bounds (recentered on 0,0): {bounds}")
        # The prepare_dem call needs the GEOGRAPHIC bounds for the
        # actual reproject so we get real DEM pixels, then we override
        # the sidecar bounds afterward. Pass via a closure-style hack:
        # we'll patch the sidecar post-hoc below.
        _geo_bounds_for_reproject = geo_bounds
        _world_bounds_for_sidecar = bounds
    else:
        bounds = tuple(args.bounds_world_xz)
        _geo_bounds_for_reproject = bounds
        _world_bounds_for_sidecar = bounds

    print(f"tx_dem_prepare: id={args.id}")
    print(f"  source: {args.source}")
    print(f"  bundle: {args.bundle}")
    prepare_dem(
        source_path=args.source,
        bundle_root=args.bundle,
        dem_id=args.id,
        bounds_world_xz=_geo_bounds_for_reproject,
        target_crs=args.crs,
        attribution=args.attribution,
    )
    # Patch the sidecar with the recentered world-XZ bounds so the
    # runtime sees the DEM as anchored on (0, 0). Geographic bounds
    # were needed inside prepare_dem to actually pull DEM pixels from
    # the source CRS; runtime only cares about the world-XZ window.
    if _geo_bounds_for_reproject != _world_bounds_for_sidecar:
        sidecar_path = args.bundle / "dem" / f"{args.id}.json"
        sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
        sidecar["bounds_world_xz"] = list(_world_bounds_for_sidecar)
        sidecar["_geographic_bounds"] = list(_geo_bounds_for_reproject)
        sidecar_path.write_text(
            json.dumps(sidecar, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"  sidecar bounds_world_xz patched to {_world_bounds_for_sidecar}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
