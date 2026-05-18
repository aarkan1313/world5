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
        # Cap at 4096 in either dim to avoid runaway file sizes for v1.
        if out_width > 4096 or out_height > 4096:
            scale = max(out_width, out_height) / 4096.0
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

    # Compute elevation range from the prepared output.
    with rasterio.open(out_path) as out_src:
        arr = out_src.read(1)
        elev_min = float(arr.min())
        elev_max = float(arr.max())

    sidecar = {
        "_schema_version": 1,
        "id": dem_id,
        "path": f"dem/{dem_id}.tif",
        "crs": target_crs,
        "bounds_world_xz": list(bounds_world_xz),
        "elevation_range_m": [elev_min, elev_max],
        "source_resolution_m": float(cell_size),
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
                    required=True,
                    help="world-XZ bounds in meters (target CRS units)")
    ap.add_argument("--crs", default="EPSG:32610",
                    help="target CRS (default: EPSG:32610 / UTM zone 10N)")
    ap.add_argument("--attribution", default="",
                    help="license + attribution string for downstream display")
    args = ap.parse_args(argv)

    if not args.bundle.exists():
        print(f"bundle not found: {args.bundle}", file=sys.stderr)
        return 1
    print(f"tx_dem_prepare: id={args.id}")
    print(f"  source: {args.source}")
    print(f"  bundle: {args.bundle}")
    prepare_dem(
        source_path=args.source,
        bundle_root=args.bundle,
        dem_id=args.id,
        bounds_world_xz=tuple(args.bounds_world_xz),
        target_crs=args.crs,
        attribution=args.attribution,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
