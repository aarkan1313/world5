"""W4 tx_family — palette-lock validation prototype.

Takes a folder of N variant albedos from one prompt (same prompt,
different seeds — these are "cousins"). Constrains them to share
a palette via histogram matching in LAB-L (luminance) and per-channel
mean/std in LAB-a/b (chroma). Outputs the locked siblings + a report
on pre/post palette drift.

Goal: validate the stochastic-texturing wishlist's claim that we can
turn FLUX cousins (drift in palette + content) into siblings (only
content varies, palette locked). If post-lock drift is small enough,
the siblings approach is viable as wishlist's MVP-floor.

This is a PROTOTYPE — measures viability. Not production code.
Future tx_family would also do edge-match (for Wang-tile siblings)
and per-block palette specs (for the AAA building-block path).

Usage:
    python tx_family.py --variants <dir> --out <dir> --anchor 0
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

try:
    from skimage import color as skcolor
    HAS_SKIMAGE = True
except ImportError:
    HAS_SKIMAGE = False


def _rgb_to_lab(rgb_u8: np.ndarray) -> np.ndarray:
    """sRGB uint8 -> LAB float32. Uses skimage if available, else approx."""
    if HAS_SKIMAGE:
        return skcolor.rgb2lab(rgb_u8 / 255.0).astype(np.float32)
    # Cheap approximation — luminance + pseudo-chroma. Less accurate
    # but doesn't require skimage.
    rgb_n = rgb_u8.astype(np.float32) / 255.0
    L = (0.2126 * rgb_n[..., 0] + 0.7152 * rgb_n[..., 1] + 0.0722 * rgb_n[..., 2]) * 100
    a = (rgb_n[..., 0] - rgb_n[..., 1]) * 50
    b = (rgb_n[..., 1] - rgb_n[..., 2]) * 50
    return np.stack([L, a, b], axis=-1).astype(np.float32)


def _lab_to_rgb(lab: np.ndarray) -> np.ndarray:
    """LAB float32 -> sRGB uint8."""
    if HAS_SKIMAGE:
        return (skcolor.lab2rgb(lab) * 255).clip(0, 255).astype(np.uint8)
    # Inverse of the approx above
    L = lab[..., 0] / 100.0
    a = lab[..., 1] / 50.0
    b = lab[..., 2] / 50.0
    r = np.clip(L + a * 0.5, 0, 1)
    g = np.clip(L - a * 0.5 + b * 0.25, 0, 1)
    bl = np.clip(L - b * 0.5, 0, 1)
    return (np.stack([r, g, bl], axis=-1) * 255).astype(np.uint8)


def _histogram_match_l(src_L: np.ndarray, ref_L: np.ndarray) -> np.ndarray:
    """Match `src_L` luminance histogram to `ref_L`. Both float32 LAB-L (0..100)."""
    # Build CDFs in 256 bins over 0..100
    bins = 256
    src_hist, _ = np.histogram(src_L.ravel(), bins=bins, range=(0.0, 100.0))
    ref_hist, _ = np.histogram(ref_L.ravel(), bins=bins, range=(0.0, 100.0))
    src_cdf = np.cumsum(src_hist).astype(np.float64)
    src_cdf /= max(src_cdf[-1], 1)
    ref_cdf = np.cumsum(ref_hist).astype(np.float64)
    ref_cdf /= max(ref_cdf[-1], 1)
    # For each src bin, find the ref bin where CDF crosses
    mapping = np.interp(src_cdf, ref_cdf, np.linspace(0, 100, bins))
    # Apply mapping to src_L
    src_bin = np.clip(((src_L / 100.0) * (bins - 1)).astype(np.int32), 0, bins - 1)
    return mapping[src_bin].astype(np.float32)


def _chroma_match(src_chroma: np.ndarray, ref_chroma: np.ndarray) -> np.ndarray:
    """Match mean+std of one chroma channel."""
    src_mean = float(src_chroma.mean())
    src_std = float(src_chroma.std() + 1e-6)
    ref_mean = float(ref_chroma.mean())
    ref_std = float(ref_chroma.std() + 1e-6)
    return ((src_chroma - src_mean) * (ref_std / src_std) + ref_mean).astype(np.float32)


def palette_distance(rgb_a_u8: np.ndarray, rgb_b_u8: np.ndarray,
                     bins: int = 32) -> float:
    """Earth-mover-ish distance on per-channel histograms. Crude but
    consistent. Returns a score in 0..1+; lower = closer palettes."""
    a = rgb_a_u8.astype(np.float32) / 255.0
    b = rgb_b_u8.astype(np.float32) / 255.0
    total = 0.0
    for ch in range(3):
        h_a, _ = np.histogram(a[..., ch].ravel(), bins=bins, range=(0.0, 1.0))
        h_b, _ = np.histogram(b[..., ch].ravel(), bins=bins, range=(0.0, 1.0))
        h_a = h_a / max(h_a.sum(), 1)
        h_b = h_b / max(h_b.sum(), 1)
        cdf_a = np.cumsum(h_a)
        cdf_b = np.cumsum(h_b)
        total += float(np.abs(cdf_a - cdf_b).mean())
    return total / 3.0


def lock_to_anchor(variant_paths: list[Path], anchor_idx: int,
                   out_dir: Path) -> dict:
    """Load N variants. Anchor = variant_paths[anchor_idx]. Lock the
    others to the anchor's palette via LAB hist-match + chroma stats
    match. Save locked siblings + a report.

    Returns the report dict.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    variants = [np.asarray(Image.open(p).convert("RGB")) for p in variant_paths]
    anchor_rgb = variants[anchor_idx]
    anchor_lab = _rgb_to_lab(anchor_rgb)

    # Pre-lock palette distance from anchor
    pre_dists = []
    for i, v in enumerate(variants):
        if i == anchor_idx:
            pre_dists.append(0.0)
        else:
            pre_dists.append(palette_distance(anchor_rgb, v))

    locked_rgbs: list[np.ndarray] = []
    for i, v in enumerate(variants):
        if i == anchor_idx:
            locked_rgbs.append(v.copy())
            continue
        v_lab = _rgb_to_lab(v)
        L_locked = _histogram_match_l(v_lab[..., 0], anchor_lab[..., 0])
        a_locked = _chroma_match(v_lab[..., 1], anchor_lab[..., 1])
        b_locked = _chroma_match(v_lab[..., 2], anchor_lab[..., 2])
        locked_lab = np.stack([L_locked, a_locked, b_locked], axis=-1)
        locked_rgb = _lab_to_rgb(locked_lab)
        locked_rgbs.append(locked_rgb)

    # Post-lock palette distance from anchor
    post_dists = []
    for i, v in enumerate(locked_rgbs):
        if i == anchor_idx:
            post_dists.append(0.0)
        else:
            post_dists.append(palette_distance(anchor_rgb, v))

    # Save locked siblings
    for i, locked in enumerate(locked_rgbs):
        Image.fromarray(locked).save(out_dir / f"sibling_v{i}.png")

    report = {
        "n_variants": len(variants),
        "anchor_idx": anchor_idx,
        "has_skimage": HAS_SKIMAGE,
        "palette_dist_to_anchor": {
            "pre_lock": pre_dists,
            "post_lock": post_dists,
            "mean_pre": float(np.mean(pre_dists)),
            "mean_post": float(np.mean(post_dists)),
            "improvement_factor": float(np.mean(pre_dists)
                                        / max(np.mean(post_dists), 1e-9)),
        },
        "variant_paths": [str(p) for p in variant_paths],
    }
    (out_dir / "family_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8")
    return report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", required=True, type=Path,
                    help="dir containing v0_albedo.png .. vN_albedo.png")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--anchor", type=int, default=0,
                    help="index of variant to use as palette anchor")
    args = ap.parse_args()

    paths = sorted(args.variants.glob("v*_albedo.png"))
    # Filter out pre-delight backups
    paths = [p for p in paths if ".pre_delight" not in p.name]
    if len(paths) < 2:
        raise SystemExit(f"need at least 2 variants under {args.variants}; "
                         f"found {len(paths)}")
    report = lock_to_anchor(paths, args.anchor, args.out)
    print(f"\n=== palette-lock report ===")
    print(f"  variants:        {report['n_variants']}")
    print(f"  anchor:          v{report['anchor_idx']}")
    print(f"  skimage:         {report['has_skimage']}")
    print(f"  pre-lock dist:   {report['palette_dist_to_anchor']['mean_pre']:.4f}")
    print(f"  post-lock dist:  {report['palette_dist_to_anchor']['mean_post']:.4f}")
    print(f"  improvement:     {report['palette_dist_to_anchor']['improvement_factor']:.1f}x")
    print(f"\nwrote {args.out}/family_report.json + sibling_v*.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
