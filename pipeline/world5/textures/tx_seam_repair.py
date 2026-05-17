"""W4 tx_seam_repair — PatchMatch quilting over the offset cross.

Wraps the upstream seam_repair.py's pure functions to fix the midline
seam that the 4-pass FLUX heal leaves behind. The audit got this stage
wrong — it thought seam_repair was duplicating the FLUX heal, but the
two stages do different things:

  - Pass 3 of tx_seamless (FLUX heal) closes the WRAP-AROUND seam at
    the texture edges.
  - tx_seam_repair (this) closes the MIDLINE seam that the reverse-
    shift in Pass 4 leaves at column W/2 and row H/2.

Without this stage, edge_continuity passes (wrap seam closed) but
the texture has visible cross-lines at the 50% marks when tiled.
Diagnosed 2026-05-12 against materials/biome_alpine/ground/ which
had clean midlines because it ran upstream seam_repair.

Behavior:
  - Runs on albedo first (compute_repair_plan)
  - Replays the same plan on every other map so all 5 stay spatially
    aligned (no normal-vs-albedo drift)
  - Backs up each map as <map>.pre_repair.png
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, r"D:/assets/pipelines/textures")
from seam_repair import (  # noqa: E402
    apply_repair_plan, compute_repair_plan,
)


MAPS = ("albedo", "normal", "roughness", "ao", "height", "metallic")


def repair_material_dir(material_dir: Path, patch: int = 64,
                        feather: int = 12, backup: bool = True) -> dict:
    """Run seam-repair on every map in a W4 candidate dir.

    Expects W4 canonical filenames: albedo.png, normal.png, etc.
    Returns a log dict.
    """
    albedo_path = material_dir / "albedo.png"
    if not albedo_path.exists():
        raise FileNotFoundError(f"albedo.png not found in {material_dir}")

    arr = np.asarray(Image.open(albedo_path).convert("RGB"))
    plan = compute_repair_plan(arr, patch=patch)
    log = {
        "module": "tx_seam_repair",
        "patch": patch,
        "feather": feather,
        "plan_ops": len(plan),
        "maps_processed": [],
        "maps_skipped": [],
    }

    for m in MAPS:
        p = material_dir / f"{m}.png"
        if not p.exists():
            log["maps_skipped"].append(m)
            continue
        if backup:
            bk = p.with_suffix(".pre_repair.png")
            if not bk.exists():
                shutil.copy2(p, bk)
        # Load — preserve mode (RGB for albedo/normal, L for grayscale maps)
        img = Image.open(p)
        mode = img.mode
        # The repair operates on RGB arrays; for single-channel maps we
        # stack to 3ch, repair, then take channel 0.
        rgb_in = img.convert("RGB")
        arr_in = np.asarray(rgb_in)
        repaired = apply_repair_plan(arr_in, plan, patch=patch,
                                     feather=feather)
        if mode == "L":
            # collapse back to single channel using the mean across RGB
            # (apply_repair_plan replays the same plan; channels stay
            # identical for grayscale-stacked inputs)
            out_arr = repaired[..., 0]
            Image.fromarray(out_arr, mode="L").save(p)
        else:
            Image.fromarray(repaired, mode="RGB").save(p)
        log["maps_processed"].append(m)
    return log


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--material", type=Path, required=True)
    ap.add_argument("--patch", type=int, default=64)
    ap.add_argument("--feather", type=int, default=12)
    ap.add_argument("--no-backup", action="store_true")
    args = ap.parse_args()
    log = repair_material_dir(args.material, patch=args.patch,
                              feather=args.feather,
                              backup=not args.no_backup)
    print(json.dumps(log, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
