"""W4 tx_variant_select — generate N variants, score by composite, keep all.

Replaces the upstream variant_select.py pattern of "generate 4, pick
lowest seam score, throw away 3." Audit finding: the seam-score
ranking is wrong because:
  1. seam-repair runs after anyway, so seam-score will get cleaned up
  2. variation between the 4 candidates is aesthetic, not seam-quality
  3. throwing away 3 is wasteful when those 3 might be visually better

W4 behavior:
  - Generate N variants at different seeds
  - Score each by composite of edge_seam + periodic_locality + richness
  - Keep ALL variants on disk for human review
  - Rank them; mark a "best by composite" but caller can override
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

from .tx_seamless import run_seamless, edge_seam_score


def _periodic_locality(rgb: np.ndarray) -> float:
    """FFT peak-locality. Same shape as texture_qa's periodic_artifact.

    Returns the ratio of brightest-AC-peak inner-window-max to outer-
    window-median. High = lattice-like; low = natural texture.
    """
    h, w = rgb.shape[:2]
    gray = rgb.mean(axis=-1).astype(np.float32)
    gray = gray - gray.mean()
    hann_y = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(h) / max(h - 1, 1))
    hann_x = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(w) / max(w - 1, 1))
    windowed = gray * np.outer(hann_y, hann_x)
    F = np.fft.fft2(windowed)
    P_shift = np.fft.fftshift(np.abs(F) ** 2)
    cy, cx = h // 2, w // 2
    rmask = max(8, min(h, w) // 64)
    yy, xx = np.indices(P_shift.shape)
    in_dc = (np.abs(yy - cy) <= rmask) & (np.abs(xx - cx) <= rmask)
    P_search = P_shift.copy()
    P_search[in_dc] = 0.0
    py, px = np.unravel_index(int(np.argmax(P_search)), P_search.shape)
    inner = 3
    outer = 12
    inner_max = float(P_shift[max(0, py - inner): py + inner + 1,
                              max(0, px - inner): px + inner + 1].max())
    outer_med = float(np.median(
        P_shift[max(0, py - outer): py + outer + 1,
                max(0, px - outer): px + outer + 1]))
    return inner_max / max(outer_med, 1e-9)


def _richness(rgb: np.ndarray) -> float:
    """Cheap content-presence score. Defends against flat-color winners."""
    gray = rgb.mean(axis=-1).astype(np.float32) / 255.0
    # luminance entropy (bin into 32 levels)
    hist, _ = np.histogram(gray, bins=32, range=(0.0, 1.0))
    p = hist[hist > 0] / hist.sum()
    entropy = float(-(p * np.log2(p)).sum())  # 0..5 for 32 bins
    # gradient activity
    gy = np.diff(gray, axis=0)
    gx = np.diff(gray, axis=1)
    grad = float(np.sqrt(gx[:-1] ** 2 + gy[:, :-1] ** 2).mean())
    return 0.6 * (entropy / 5.0) + 0.4 * min(grad * 10, 1.0)


def composite_score(seam: float, periodic: float, richness: float) -> float:
    """Combine the three into a single score in 0..1, higher is better.

    Normalization:
      seam: 0 (clean) -> 0.02 (bad). Maps to 1..0 via clip.
      periodic: ~6 (good) -> ~25 (bad). Maps to 1..0 via clip.
      richness: already 0..1.
    """
    seam_n = max(0.0, min(1.0, 1.0 - seam / 0.02))
    periodic_n = max(0.0, min(1.0, 1.0 - (periodic - 6) / (25 - 6)))
    rich_n = max(0.0, min(1.0, richness))
    return 0.4 * seam_n + 0.4 * periodic_n + 0.2 * rich_n


def score_variant(rgb: np.ndarray) -> dict:
    seam = edge_seam_score(rgb)
    periodic = _periodic_locality(rgb)
    rich = _richness(rgb)
    composite = composite_score(seam, periodic, rich)
    return {
        "edge_seam": round(seam, 6),
        "periodic_locality": round(periodic, 3),
        "richness": round(rich, 3),
        "composite": round(composite, 4),
    }


def generate_variants(prompt: str, asset_id: str, n_variants: int, *,
                      unet: str, clip: str, vae: str, size: int,
                      steps: int, seed_base: int, heal_denoise: float,
                      heal_mode: str, host: str,
                      out_dir: Path) -> list[dict]:
    """Generate N variants, save all to out_dir, return ranked list."""
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for i in range(n_variants):
        seed = seed_base + i * 1000
        variant_id = f"{asset_id}_v{i}"
        print(f"\n[variant {i + 1}/{n_variants}] seed={seed}")
        try:
            final, log = run_seamless(
                prompt, variant_id,
                unet=unet, clip=clip, vae=vae, size=size, seed=seed,
                steps=steps, heal_denoise=heal_denoise, heal_mode=heal_mode,
                host=host,
            )
        except Exception as e:
            print(f"  variant {i} FAILED: {e}")
            results.append({
                "variant_index": i,
                "seed": seed,
                "error": str(e),
            })
            continue
        # Save the raw albedo
        path = out_dir / f"v{i}_albedo.png"
        Image.fromarray(final).save(path)
        scores = score_variant(final)
        scores["variant_index"] = i
        scores["seed"] = seed
        scores["path"] = str(path.relative_to(out_dir))
        scores["seamless_log"] = log
        results.append(scores)
        print(f"  scores: seam={scores['edge_seam']:.5f} "
              f"periodic={scores['periodic_locality']:.2f} "
              f"richness={scores['richness']:.2f} "
              f"composite={scores['composite']:.3f}")
    # rank by composite (desc)
    results.sort(key=lambda r: r.get("composite", -1), reverse=True)
    # save the ranking
    ranking_path = out_dir / "ranking.json"
    ranking_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    return results


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--id", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--variants", type=int, default=4)
    ap.add_argument("--unet", default="flux-2-klein-9b-fp8.safetensors")
    ap.add_argument("--clip", default="qwen_3_8b_fp8mixed.safetensors")
    ap.add_argument("--vae", default="flux2-vae.safetensors")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--steps", type=int, default=4)
    ap.add_argument("--seed-base", type=int, default=42)
    ap.add_argument("--heal-denoise", type=float, default=0.35)
    ap.add_argument("--heal-mode", choices=["flux_heal", "none"],
                    default="flux_heal")
    ap.add_argument("--host", default="http://127.0.0.1:8188")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    ranking = generate_variants(
        args.prompt, args.id, args.variants,
        unet=args.unet, clip=args.clip, vae=args.vae,
        size=args.size, steps=args.steps, seed_base=args.seed_base,
        heal_denoise=args.heal_denoise, heal_mode=args.heal_mode,
        host=args.host, out_dir=out_dir,
    )
    print(f"\n=== ranking (best first) ===")
    for r in ranking:
        if "error" in r:
            print(f"  v{r['variant_index']} FAILED: {r['error']}")
            continue
        print(f"  v{r['variant_index']} composite={r['composite']:.3f}  "
              f"seam={r['edge_seam']:.5f}  "
              f"periodic={r['periodic_locality']:.2f}  "
              f"richness={r['richness']:.2f}")
    print(f"\nwrote {out_dir/'ranking.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
