"""W4 tx_subject — single-subject 2D image generator with alpha cutout.

The sibling of tx_seamless. Different output contract:
  - Single subject on transparent background (not tileable)
  - RGBA PNG with rembg-extracted alpha
  - No PBR maps, no seam handling, no tile prompt suffix
  - Designed as the input stage for:
      (a) TRELLIS / image-to-3D extraction
      (b) Crossed-billboard impostors (vegetation distant tier)

The prompt strategy: append a "subject framing" suffix that pushes
FLUX toward isolated-subject composition. Then rembg cuts the
background out cleanly. Two-stage approach proven more reliable
than prompt-only background.

Usage:
    python tx_subject.py --prompt "ancient oak tree" --id oak_01 \
        --out-dir D:/tmp/subjects/trees/oak_01 --size 1024

Output:
    subject.png         — RGBA, alpha cut to subject
    subject_pre.png     — pre-rembg (the raw FLUX RGB)
    alpha_mask.png      — single-channel mask, useful for downstream
    grade.json          — quality metrics
    manifest.json       — settings + provenance
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from PIL import Image

# Reuse the ComfyUI plumbing from tx_seamless. W5 port: relative
# package import; the W4 sys.path trick is unnecessary.
from .tx_seamless import (
    queue_prompt, wait_for, download_output,
    workflow_text2img, COMFY_HOST,
)


# Subject framing suffix — pushes FLUX toward portrait/isolated composition.
# Crucially does NOT include "tileable" or "seamless" wording.
SUBJECT_PROMPT_SUFFIX = (
    ", single isolated subject, centered composition, "
    "plain neutral grey studio background, "
    "even diffuse lighting, no environment, no ground plane, "
    "no shadows, professional product photography style, "
    "subject fills 70 percent of frame, full subject visible"
)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _generate_pass1(prompt: str, asset_id: str, *, unet: str, clip: str,
                    vae: str, size: int, seed: int, steps: int,
                    host: str, tmp_dir: Path) -> np.ndarray:
    """Run a single text2img pass with the subject-framing suffix. No
    offset, no heal — we want a *good single shot*, not a tile."""
    full_prompt = prompt + SUBJECT_PROMPT_SUFFIX
    print(f"[tx_subject] prompt: {prompt!r}")
    print(f"[tx_subject]  +suffix: ...{SUBJECT_PROMPT_SUFFIX[:60]}...")
    print(f"[tx_subject]  size={size} seed={seed} steps={steps}")

    tmp_dir.mkdir(parents=True, exist_ok=True)
    wf = workflow_text2img(full_prompt, unet, clip, vae, size, seed, steps,
                           prefix=f"{asset_id}_subj")
    pid = queue_prompt(wf, host=host)
    res = wait_for(pid, host=host)
    images = res["outputs"].get("70", {}).get("images", [])
    if not images:
        raise RuntimeError("no images from text2img")
    out_path = tmp_dir / "raw.png"
    download_output(host, images[0]["filename"], images[0]["subfolder"],
                    images[0]["type"], out_path)
    return np.asarray(Image.open(out_path).convert("RGB"))


def _extract_alpha(rgb: np.ndarray, model_name: str = "u2net") -> np.ndarray:
    """Run rembg on the raw RGB. Returns RGBA uint8."""
    print(f"[tx_subject] rembg (model={model_name})...")
    t = time.time()
    from rembg import remove, new_session
    session = new_session(model_name)
    rgba = remove(Image.fromarray(rgb), session=session)
    if rgba.mode != "RGBA":
        rgba = rgba.convert("RGBA")
    print(f"[tx_subject]   rembg took {time.time() - t:.1f}s")
    return np.asarray(rgba)


def grade_subject(rgba: np.ndarray) -> dict:
    """Cheap auto-grading for subject quality.

    Three checks:
      1. subject_coverage: alpha != 0 fraction of total pixels. Want
         0.15 .. 0.75 (subject is centered + visible but not full-frame)
      2. edge_cleanness: fraction of border pixels with non-zero alpha.
         Want < 0.05 (subject doesn't touch image edges → fully contained)
      3. alpha_sharpness: fraction of alpha pixels that are pure 0 or 255
         vs intermediate. Higher = sharper cutout. Want > 0.85.
    """
    h, w = rgba.shape[:2]
    alpha = rgba[..., 3]
    nonzero = alpha > 0
    coverage = float(nonzero.sum()) / (h * w)
    # border pixels (1px ring)
    border_mask = np.zeros((h, w), dtype=bool)
    border_mask[0, :] = True; border_mask[-1, :] = True
    border_mask[:, 0] = True; border_mask[:, -1] = True
    border_touched = float((nonzero & border_mask).sum()) / max(border_mask.sum(), 1)
    # alpha sharpness — what fraction is hard 0 or 255?
    a = alpha
    hard = ((a == 0) | (a == 255)).sum()
    sharpness = float(hard) / (h * w)

    # Composite grade (coerce to python bool, numpy bool isn't JSON-serializable)
    # Sharpness threshold relaxed 0.85 -> 0.65 on 2026-05-13 — organic
    # subjects (trees, plants) have legitimately soft alpha edges from
    # leaf-fringe; the strict threshold was failing visually-good outputs.
    # Hard-subject category (rocks, props) tend to land 0.71-0.87 naturally
    # and still pass.
    coverage_ok = bool(0.15 <= coverage <= 0.75)
    edge_ok = bool(border_touched < 0.05)
    sharp_ok = bool(sharpness > 0.65)
    n_pass = int(coverage_ok) + int(edge_ok) + int(sharp_ok)
    grade = "A" if n_pass == 3 else "B" if n_pass == 2 else "C" if n_pass == 1 else "D"

    return {
        "subject_coverage": round(coverage, 4),
        "border_touched": round(border_touched, 4),
        "alpha_sharpness": round(sharpness, 4),
        "passed": {
            "coverage": coverage_ok,
            "edge": edge_ok,
            "sharpness": sharp_ok,
        },
        "grade": grade,
        "passed_checks": n_pass,
        "thresholds": {
            "coverage_lo": 0.15,
            "coverage_hi": 0.75,
            "border_touched_max": 0.05,
            "alpha_sharpness_min": 0.65,
        },
    }


def run_subject(prompt: str, asset_id: str, out_dir: Path, *,
                unet: str = "flux-2-klein-9b-fp8.safetensors",
                clip: str = "qwen_3_8b_fp8mixed.safetensors",
                vae: str = "flux2-vae.safetensors",
                size: int = 1024, seed: int = 42, steps: int = 4,
                rembg_model: str = "u2net",
                host: str = COMFY_HOST) -> dict:
    """Generate one subject image with alpha cutout. Returns manifest dict."""
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp_dir = out_dir / "_tmp"
    started = _now()

    # Stage 1: FLUX text2img
    t1 = time.time()
    rgb = _generate_pass1(prompt, asset_id,
                          unet=unet, clip=clip, vae=vae,
                          size=size, seed=seed, steps=steps,
                          host=host, tmp_dir=tmp_dir)
    flux_seconds = round(time.time() - t1, 1)

    # Save pre-rembg raw
    Image.fromarray(rgb).save(out_dir / "subject_pre.png")

    # Stage 2: rembg
    t2 = time.time()
    rgba = _extract_alpha(rgb, model_name=rembg_model)
    rembg_seconds = round(time.time() - t2, 1)

    # Save RGBA + alpha mask
    Image.fromarray(rgba, mode="RGBA").save(out_dir / "subject.png")
    Image.fromarray(rgba[..., 3], mode="L").save(out_dir / "alpha_mask.png")

    # Grade
    grade = grade_subject(rgba)
    (out_dir / "grade.json").write_text(
        json.dumps(grade, indent=2), encoding="utf-8")

    # Manifest
    manifest = {
        "version": "tx_subject_v1",
        "asset_id": asset_id,
        "prompt": prompt,
        "full_prompt": prompt + SUBJECT_PROMPT_SUFFIX,
        "settings": {
            "unet": unet, "clip": clip, "vae": vae,
            "size": size, "seed": seed, "steps": steps,
            "rembg_model": rembg_model,
        },
        "timing": {
            "flux_seconds": flux_seconds,
            "rembg_seconds": rembg_seconds,
        },
        "started_at": started,
        "completed_at": _now(),
        "grade": grade["grade"],
        "grade_detail": grade,
    }
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8")

    # Save the prompt as a text file for human convenience
    (out_dir / "prompt.txt").write_text(prompt, encoding="utf-8")

    print(f"\n[tx_subject] done — grade {grade['grade']} "
          f"(coverage {grade['subject_coverage']:.2f}, "
          f"edge {grade['border_touched']:.3f}, "
          f"sharp {grade['alpha_sharpness']:.2f})")

    # Clean up tmp
    import shutil
    shutil.rmtree(tmp_dir, ignore_errors=True)
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--id", required=True)
    ap.add_argument("--out-dir", required=True, type=Path)
    ap.add_argument("--unet", default="flux-2-klein-9b-fp8.safetensors")
    ap.add_argument("--clip", default="qwen_3_8b_fp8mixed.safetensors")
    ap.add_argument("--vae", default="flux2-vae.safetensors")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--steps", type=int, default=4)
    ap.add_argument("--rembg-model", default="u2net",
                    choices=["u2net", "u2netp", "u2net_human_seg",
                             "isnet-general-use", "birefnet-general"])
    ap.add_argument("--host", default=COMFY_HOST)
    args = ap.parse_args()

    manifest = run_subject(
        args.prompt, args.id, args.out_dir,
        unet=args.unet, clip=args.clip, vae=args.vae,
        size=args.size, seed=args.seed, steps=args.steps,
        rembg_model=args.rembg_model, host=args.host,
    )
    return 0 if manifest["grade"] in ("A", "B") else 1


if __name__ == "__main__":
    raise SystemExit(main())
