"""Heitz-Neyret 2018 inverse-histogram-transform LUT generator.

For each albedo.png, computes per-channel inverse CDF and writes
albedo_tinv.png alongside it (256×1, 8-bit RGB). The shader's
w5_hn_sample reads this LUT to recover contrast lost by HN's 3-tap
blend (variance correction without IHT looks washed out; with IHT it
looks like the original).

Algorithm per channel c in {R, G, B}:
    values = sorted(image[:, :, c].flatten())  # ascending
    For each output index i in [0, 255]:
        Gaussian-cdf input u = (i + 0.5) / 256
        Map u → "Gaussian-equivalent rank" by erf inverse → uniform t
        lut[i] = values[round(t * (N - 1))]

This is the inverse of the forward transform T that gaussianizes the
input. At sample time the shader blends Gaussianized values (which are
correctly variance-corrected because Gaussians sum cleanly), then
remaps via T_inv = this LUT.

Usage:
    python -m world5.textures.tx_hn_lut --world engine/worlds/walking_demo
    python -m world5.textures.tx_hn_lut --albedo path/to/albedo.png
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from PIL import Image
import numpy as np


def _erfinv(x: np.ndarray) -> np.ndarray:
    # numpy doesn't ship erfinv. scipy does; fall back to Winitzki approx.
    try:
        from scipy.special import erfinv  # type: ignore

        return erfinv(x)
    except ImportError:
        # Winitzki 2008 approximation. Max error ~1.3e-4.
        a = 0.147
        ln = np.log(1.0 - x * x + 1e-12)
        term = 2.0 / (math.pi * a) + ln / 2.0
        return np.sign(x) * np.sqrt(np.sqrt(term * term - ln / a) - term)


def compute_tinv_lut(albedo_path: Path) -> np.ndarray:
    """Return a (1, 256, 3) uint8 LUT for the given RGB albedo."""
    img = Image.open(albedo_path).convert("RGB")
    arr = np.asarray(img, dtype=np.uint8)  # (H, W, 3)
    lut = np.zeros((1, 256, 3), dtype=np.uint8)
    n = arr.shape[0] * arr.shape[1]
    for c in range(3):
        values = np.sort(arr[:, :, c].flatten())  # ascending
        # Gaussian-CDF probe points: u_i = (i + 0.5) / 256, then
        # convert to uniform rank via erf so output is the inverse of
        # the forward "Gaussianize" transform.
        i = np.arange(256, dtype=np.float64)
        u = (i + 0.5) / 256.0
        # Map u (0..1) to Gaussian quantile, then back to uniform via
        # erf to find the rank position in sorted values.
        # Standard HN: t = 0.5 * (1 + erf(erfinv(2u - 1)))  -> just u, identity.
        # The actual remap that gives histogram preservation is:
        # T_inv(u) = values[round(u * (n-1))] where u is uniform.
        # The variance correction happens in shader; LUT is just inverse-CDF.
        ranks = np.clip(np.round(u * (n - 1)).astype(np.int64), 0, n - 1)
        lut[0, :, c] = values[ranks]
    return lut


def write_lut(albedo_path: Path, lut: np.ndarray) -> Path:
    out_path = albedo_path.parent / "albedo_tinv.png"
    Image.fromarray(lut, mode="RGB").save(out_path)
    return out_path


def process_world(world_root: Path) -> int:
    """Walk world's materials/ tree, write LUT next to each albedo.png. Returns count."""
    materials = world_root / "materials"
    if not materials.is_dir():
        print(f"no materials/ dir under {world_root}", file=sys.stderr)
        return 0
    count = 0
    for albedo in sorted(materials.rglob("albedo.png")):
        lut = compute_tinv_lut(albedo)
        out = write_lut(albedo, lut)
        print(f"  {albedo.relative_to(world_root)} -> {out.name}")
        count += 1
    return count


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else "")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--world", type=Path, help="world bundle root (writes LUT next to every albedo.png)")
    src.add_argument("--albedo", type=Path, help="single albedo.png")
    args = ap.parse_args(argv)
    if args.world is not None:
        n = process_world(args.world)
        print(f"tx_hn_lut: wrote {n} LUTs under {args.world}")
        return 0
    lut = compute_tinv_lut(args.albedo)
    out = write_lut(args.albedo, lut)
    print(f"tx_hn_lut: wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
