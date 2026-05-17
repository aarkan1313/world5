"""W4 tx_pbr_hybrid — SM for tileability cleanup + derive for PBR maps.

The 2026-05-12 diagnosis chain found:
  - StableMaterials' `tileable=True` diffusion pass cleans the midline
    seam that FLUX's 4-pass heal leaves behind. (Confirmed against the
    shipped materials/biome_alpine/ground/ which had midline ratio 1.3
    where our new pipeline produced ratio 22.)
  - But SM's derived PBR maps (normal/roughness/AO from its diffusion)
    are too soft for terrain — tx_qa's mip32_stdev flags them on every
    Snow combo because SM produces uniformly-soft albedos.

So this backend uses SM for exactly the job it does well (tileable
albedo generation) and derive_pbr_v2 for the rest (PBR maps that are
mathematically consistent with the SM-cleaned albedo).

Sequence:
  1. Take the input albedo (post-FLUX, possibly post-delight).
  2. Run SM with tileable=True; keep ONLY its basecolor output.
     Discard SM's normal/roughness/metallic/height.
  3. Save that cleaned albedo as the canonical albedo.png.
  4. Run derive_pbr_v2 on the cleaned albedo for normal/roughness/AO/
     height/metallic.

Output is identical-shape to derive: albedo.png + 5 derived PBR maps,
all canonical names in out_dir.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from .tx_pbr_derive import derive_pbr as derive_pbr_heuristic

SM_PYTHON = r"D:\assets\animators\mesa-env\venv\Scripts\python.exe"
SM_SCRIPT = r"D:\assets\pipelines\textures\stablematerials_image2pbr.py"


def _run_sm_tileable_albedo(input_albedo: Path, out_dir: Path,
                            size: int = 512) -> Path:
    """Run SM in tileable mode, return the path to its albedo output.

    SM writes <id>_<map>.png to out_dir; we use a fixed id and pick out
    just the albedo. Caller is responsible for cleaning up out_dir if
    it's a tempdir.
    """
    cmd = [
        SM_PYTHON, SM_SCRIPT,
        "--input", str(input_albedo),
        "--out", str(out_dir),
        "--id", "sm_tileable",
        "--mode", "standard",
        "--size", str(size),
    ]
    print(f"[tx_pbr_hybrid] SM tileable pass (size={size})")
    result = subprocess.run(cmd, capture_output=False)
    if result.returncode != 0:
        raise RuntimeError(f"StableMaterials failed rc={result.returncode}")
    sm_albedo = out_dir / "sm_tileable_albedo.png"
    if not sm_albedo.exists():
        raise RuntimeError(f"SM produced no albedo at {sm_albedo}")
    return sm_albedo


def derive_pbr(input_albedo: Path, out_dir: Path, *, category: str,
               sm_size: int = 1024,
               normal_strength: float = 4.0,
               snow_mode: bool | None = None) -> dict:
    """Run the hybrid PBR pipeline.

    Args:
        input_albedo: post-FLUX raw albedo (will be replaced by SM's
            tileable-cleaned version)
        out_dir: where to write canonical maps (albedo + 5 derived PBR)
        category: drives derive_pbr_v2's roughness preset
        sm_size: resolution to run SM at. SM's native is 512; if input
            is 1024, SM upscales internally then we keep 1024.
        normal_strength: passed to derive_pbr
        snow_mode: passed to derive_pbr (auto-detect based on category)

    Returns log dict.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    sm_tmp = Path(tempfile.mkdtemp(prefix="tx_hybrid_sm_"))
    try:
        # Step 1+2: SM tileable albedo cleanup
        sm_albedo = _run_sm_tileable_albedo(input_albedo, sm_tmp,
                                             size=sm_size)

        # Step 3: save SM-cleaned albedo as the canonical albedo.png
        # (derive_pbr will then read from this file)
        canonical = out_dir / "albedo.png"
        shutil.copy2(sm_albedo, canonical)

        # Step 4: run derive_pbr_v2 on the cleaned albedo
        derive_log = derive_pbr_heuristic(
            canonical, out_dir,
            category=category,
            normal_strength=normal_strength,
            snow_mode=snow_mode,
        )

        return {
            "backend": "tx_pbr_hybrid",
            "sm_size": sm_size,
            "category": category,
            "sm_input": str(input_albedo),
            "derive_log": derive_log,
            "maps": derive_log["maps"],
        }
    finally:
        shutil.rmtree(sm_tmp, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--albedo", type=Path, required=True,
                    help="post-FLUX raw albedo (will be cleaned by SM)")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--category", default="Rock")
    ap.add_argument("--sm-size", type=int, default=1024)
    ap.add_argument("--normal-strength", type=float, default=4.0)
    args = ap.parse_args()
    log = derive_pbr(args.albedo, args.out,
                     category=args.category,
                     sm_size=args.sm_size,
                     normal_strength=args.normal_strength)
    print(json.dumps(log, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
