"""Phase 5.7 demonstration: bake walking_demo's alpine kernel chain
(noise_stack + erosion) over a region + render a before/after PNG.

Proves that:
1. KernelComposer.bake_page actually runs erosion stages in real
   walking_demo catalogs (not just synthetic test fixtures)
2. Erosion produces visibly different terrain (valleys, drainage,
   slumped peaks) vs the noise-only baseline
3. spec 12 content-addressed cache works end-to-end (second bake
   skips compute, just reads bytes)

What this is NOT: a runtime wiring of Composer into the live
walking_demo loader. The runtime still consumes
`kernels/noise_stack.json` directly; switching the loader to be
catalog-driven is a separate refactor. This script is the
*proof-it-works* demo, run offline.

Usage:
    python -m world5.demo.bake_walking_demo_erosion

Output:
    engine/worlds/walking_demo/captures/erosion_comparison.png
    engine/worlds/walking_demo/captures/erosion_comparison.json
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
from PIL import Image

from world5.content_address import ContentAddressStore
from world5.kernels import KernelComposer, NoiseStackKernel


# --- paths ---

_PIPELINE_ROOT = Path(__file__).resolve().parents[3]
_WALKING_DEMO = _PIPELINE_ROOT / "engine" / "worlds" / "walking_demo"
_CATALOG_PATH = _WALKING_DEMO / "biome_catalog.json"
_CAPTURES_DIR = _WALKING_DEMO / "captures"
_CACHE_DIR = _PIPELINE_ROOT / "pipeline" / ".content_addressed_store" / "kernel_bakes"


# --- bake parameters ---

WORLD_ORIGIN_XZ = (-512.0, -512.0)  # bottom-left of the demo region
EXTENT_M = 1024.0                    # 1km × 1km region
GRID_N = 256                         # 4m per cell
SEED = 42


def _height_to_grayscale(arr: np.ndarray) -> np.ndarray:
    """Normalize a height array to uint8 [0, 255] for visualization.
    Uses a common [-100m, +100m] range so before/after comparison
    uses the same color mapping."""
    fixed_min, fixed_max = -100.0, 100.0
    norm = np.clip((arr - fixed_min) / (fixed_max - fixed_min), 0.0, 1.0)
    return (norm * 255.0).astype(np.uint8)


def _hillshade(height: np.ndarray, sun_az_deg: float = 315.0,
               sun_alt_deg: float = 45.0,
               z_exaggeration: float = 2.0) -> np.ndarray:
    """Lambertian hillshade. Brings out terrain shape much more
    clearly than raw grayscale heights. Returns uint8 [0, 255]."""
    az = np.radians(sun_az_deg)
    alt = np.radians(sun_alt_deg)
    sun = np.array([
        np.cos(alt) * np.sin(az),
        np.cos(alt) * np.cos(az),
        np.sin(alt),
    ])
    # Per-cell normal via central difference, scaled by exaggeration.
    h = height * z_exaggeration
    gy, gx = np.gradient(h)
    normal = np.stack([-gx, -gy, np.ones_like(h)], axis=-1)
    norm_len = np.linalg.norm(normal, axis=-1, keepdims=True)
    normal = normal / np.maximum(norm_len, 1e-6)
    shade = np.einsum("ijk,k->ij", normal, sun)
    shade = np.clip(shade, 0.0, 1.0)
    return (shade * 255.0).astype(np.uint8)


def _side_by_side(left: np.ndarray, right: np.ndarray,
                  gap: int = 8) -> np.ndarray:
    """Stack two same-shaped images horizontally with a black gap."""
    h, w = left.shape[:2]
    canvas = np.zeros((h, w * 2 + gap, 3), dtype=np.uint8)
    canvas[:, :w] = np.stack([left] * 3, axis=-1) \
        if left.ndim == 2 else left
    canvas[:, w + gap:] = np.stack([right] * 3, axis=-1) \
        if right.ndim == 2 else right
    return canvas


def main() -> int:
    print(f"[bake_demo] reading catalog: {_CATALOG_PATH}")
    catalog = json.loads(_CATALOG_PATH.read_text(encoding="utf-8"))

    # Build composer from the real catalog (alpine has chain:
    # noise_stack + erosion per the 5.7 demo amendment).
    composer = KernelComposer(catalog)
    print(f"[bake_demo] biomes: {composer.biome_names}")

    alpine_idx = composer.biome_names.index("alpine")
    alpine_biome = composer._biomes[alpine_idx]  # noqa: SLF001 — demo
    chain_types = [type(s).__name__ for s in alpine_biome.instantiated_stages]
    print(f"[bake_demo] alpine chain: {chain_types}")
    if "ErosionKernel" not in chain_types:
        print("[bake_demo] WARNING: alpine catalog has no erosion stage; "
              "comparison will show noise-only on both sides")

    # Set up the content-addressed cache.
    store = ContentAddressStore(store_root=_CACHE_DIR, cap_gb=0.5)
    print(f"[bake_demo] cache root: {_CACHE_DIR}")

    # Bake the eroded chain.
    print(f"[bake_demo] baking eroded (grid={GRID_N}, extent={EXTENT_M}m)...")
    t0 = time.monotonic()
    eroded = composer.bake_page(
        world_origin_xz=WORLD_ORIGIN_XZ,
        extent_m=EXTENT_M,
        grid_n=GRID_N,
        seed=SEED,
        store=store,
        biome_index=alpine_idx,
    )
    eroded_s = time.monotonic() - t0
    print(f"[bake_demo]   eroded bake: {eroded_s:.2f}s "
          f"(min/max: {eroded.min():.2f} / {eroded.max():.2f} m)")

    # Bake again to demonstrate the cache hit.
    t0 = time.monotonic()
    _ = composer.bake_page(
        world_origin_xz=WORLD_ORIGIN_XZ,
        extent_m=EXTENT_M,
        grid_n=GRID_N,
        seed=SEED,
        store=store,
        biome_index=alpine_idx,
    )
    eroded_hit_s = time.monotonic() - t0
    print(f"[bake_demo]   eroded cache hit: {eroded_hit_s:.3f}s "
          f"(speedup: {eroded_s / max(eroded_hit_s, 0.001):.0f}x)")

    # Bake the noise-only baseline directly via the base kernel
    # (bypass the composer to skip erosion).
    base_kernel = alpine_biome.instantiated_stages[0]
    if not isinstance(base_kernel, NoiseStackKernel):
        print("[bake_demo] ERROR: first stage isn't NoiseStackKernel; aborting")
        return 2
    print(f"[bake_demo] baking noise-only baseline...")
    t0 = time.monotonic()
    noise_only = base_kernel.sample_page(
        WORLD_ORIGIN_XZ, extent_m=EXTENT_M, grid_n=GRID_N, seed=SEED)
    noise_s = time.monotonic() - t0
    print(f"[bake_demo]   noise-only: {noise_s:.2f}s "
          f"(min/max: {noise_only.min():.2f} / {noise_only.max():.2f} m)")

    # Difference stats — proves erosion actually changed things.
    diff = eroded - noise_only
    delta_mean = float(np.abs(diff).mean())
    delta_max = float(np.abs(diff).max())
    cells_changed = int((np.abs(diff) > 0.5).sum())
    pct_changed = 100.0 * cells_changed / diff.size
    print(f"[bake_demo] delta: mean abs={delta_mean:.3f}m  "
          f"max abs={delta_max:.3f}m  cells>0.5m={cells_changed} "
          f"({pct_changed:.1f}%)")

    # Render comparison PNG: hillshade noise-only | hillshade eroded
    print(f"[bake_demo] rendering comparison PNG...")
    noise_shade = _hillshade(noise_only)
    eroded_shade = _hillshade(eroded)
    comparison = _side_by_side(noise_shade, eroded_shade)
    _CAPTURES_DIR.mkdir(parents=True, exist_ok=True)
    out_png = _CAPTURES_DIR / "erosion_comparison.png"
    Image.fromarray(comparison).save(out_png)
    print(f"[bake_demo]   wrote {out_png}")

    # Also save the raw heightmaps as grayscale for inspection.
    Image.fromarray(_height_to_grayscale(noise_only)).save(
        _CAPTURES_DIR / "erosion_baseline_noise.png")
    Image.fromarray(_height_to_grayscale(eroded)).save(
        _CAPTURES_DIR / "erosion_eroded_height.png")

    # JSON manifest.
    manifest = {
        "phase": "5.7 demonstration",
        "world_origin_xz": list(WORLD_ORIGIN_XZ),
        "extent_m": EXTENT_M,
        "grid_n": GRID_N,
        "seed": SEED,
        "alpine_chain": chain_types,
        "bake_duration_s": eroded_s,
        "cache_hit_duration_s": eroded_hit_s,
        "cache_speedup_factor": eroded_s / max(eroded_hit_s, 0.001),
        "noise_only_baseline_duration_s": noise_s,
        "delta_mean_abs_m": delta_mean,
        "delta_max_abs_m": delta_max,
        "cells_changed_gt_half_m": cells_changed,
        "cells_changed_pct": pct_changed,
        "outputs": {
            "comparison_png": str(out_png),
            "baseline_png": str(_CAPTURES_DIR / "erosion_baseline_noise.png"),
            "eroded_png": str(_CAPTURES_DIR / "erosion_eroded_height.png"),
        },
    }
    manifest_path = _CAPTURES_DIR / "erosion_comparison.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"[bake_demo]   wrote {manifest_path}")

    print(f"\n[bake_demo] DONE. View: {out_png}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
