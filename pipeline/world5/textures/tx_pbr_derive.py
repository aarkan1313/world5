"""W4 tx_pbr_derive — heuristic PBR derivation, default backend.

Wraps the pure-function part of D:/assets/pipelines/textures/derive_pbr_v2.py
without the catalog-write side effects. Per the audit, this becomes
W4's default PBR backend because:
  - maps are mathematically derived from the albedo, so they can't
    visually disagree with it (StableMaterials sometimes invents detail
    the albedo doesn't have)
  - deterministic + cheap + fast
  - for terrain at distance (top-down) the subtle SM micro-detail
    doesn't read anyway

Differences vs upstream:
  - no catalog write
  - canonical map names (albedo.png, not <id>_albedo.png)
  - per-category roughness presets extended for terrain-soft (snow, sand)
  - `snow_mode=True` swaps in a roughness curve that doesn't darken-with-luma
    (which makes snow look weirdly contrasty)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Import the helper functions from upstream — we want the same math,
# we just don't want the upstream's __main__ behavior.
sys.path.insert(0, r"D:/assets/pipelines/textures")
from derive_pbr_v2 import (  # noqa: E402
    derive_ao, derive_height, derive_metallic, derive_normal,
    luminance, ROUGHNESS_PRESETS,
)


# W4 roughness presets — extended for terrain materials. Keep the
# upstream values intact where they exist (so behavior matches when
# the user passes a known category); add tuned ones for terrain-soft.
W4_ROUGHNESS_PRESETS = {
    **ROUGHNESS_PRESETS,
    "Snow":    (0.96, 0.04),  # very rough, very low variance
    "Sand":    (0.92, 0.06),
    "Ground":  (0.88, 0.10),
    "Foliage": (0.85, 0.12),
    "Mixed":   (0.85, 0.12),  # rocky+snow mid slots
    # Rock + Wood + others come from upstream
}


def derive_roughness_w4(albedo: np.ndarray, category: str,
                        snow_mode: bool = False) -> np.ndarray:
    """W4 roughness derivation.

    Upstream's `derive_roughness` darkens roughness where the albedo
    is bright. For snow that's exactly backwards — bright snow IS
    high-roughness. snow_mode flips the relation so brighter -> rougher
    rather than brighter -> smoother.
    """
    mean, contrast = W4_ROUGHNESS_PRESETS.get(category,
                                              W4_ROUGHNESS_PRESETS["default"])
    lum = luminance(albedo / 255.0)
    saturation = (albedo.max(axis=-1) - albedo.min(axis=-1)) / 255.0
    detail = (lum - lum.mean()) * contrast
    detail += (saturation - saturation.mean()) * (contrast * 0.5)
    if snow_mode:
        # Flip the luma contribution: brighter pixels get rougher, not
        # smoother. Saturation contribution stays the same direction.
        detail = -detail + (saturation - saturation.mean()) * contrast
    rough = np.clip(mean + detail, 0.0, 1.0)
    return (rough * 255).astype(np.uint8)


def derive_pbr(albedo_path: Path, out_dir: Path, *, category: str,
               normal_strength: float = 4.0,
               snow_mode: bool | None = None) -> dict:
    """Derive height/normal/ao/roughness/metallic from albedo.

    Writes 5 maps + a copy of the albedo into `out_dir` with W4
    canonical names: albedo.png / normal.png / roughness.png / ao.png /
    height.png / metallic.png.

    `snow_mode` defaults to True for Snow/Foliage categories where the
    upstream luma -> roughness relationship is wrong.

    Returns a log dict describing what was derived.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    rgb = np.asarray(Image.open(albedo_path).convert("RGB"), dtype=np.uint8)
    albedo_lum = luminance(rgb / 255.0)

    if snow_mode is None:
        snow_mode = category in ("Snow", "Foliage", "Mixed")

    height = derive_height(albedo_lum)
    normal = derive_normal(height, strength=normal_strength)
    ao = derive_ao(height)
    rough = derive_roughness_w4(rgb, category, snow_mode=snow_mode)
    metal = derive_metallic(category, rgb.shape[:2])

    Image.fromarray((height * 255).astype(np.uint8), mode="L").save(out_dir / "height.png")
    Image.fromarray(normal, mode="RGB").save(out_dir / "normal.png")
    Image.fromarray(ao, mode="L").save(out_dir / "ao.png")
    Image.fromarray(rough, mode="L").save(out_dir / "roughness.png")
    Image.fromarray(metal, mode="L").save(out_dir / "metallic.png")
    Image.fromarray(rgb, mode="RGB").save(out_dir / "albedo.png")

    return {
        "backend": "tx_pbr_derive",
        "category": category,
        "snow_mode": snow_mode,
        "normal_strength": normal_strength,
        "maps": ["albedo", "normal", "roughness", "ao", "height", "metallic"],
        "preset_used": W4_ROUGHNESS_PRESETS.get(
            category, W4_ROUGHNESS_PRESETS["default"]),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--albedo", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--category", default="Rock")
    ap.add_argument("--normal-strength", type=float, default=4.0)
    ap.add_argument("--snow-mode", action="store_true",
                    help="force snow-style roughness inversion regardless of category")
    args = ap.parse_args()
    log = derive_pbr(args.albedo, args.out,
                     category=args.category,
                     normal_strength=args.normal_strength,
                     snow_mode=args.snow_mode or None)
    import json
    print(json.dumps(log, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
