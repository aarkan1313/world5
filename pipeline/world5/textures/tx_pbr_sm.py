"""W4 tx_pbr_sm — StableMaterials backend (opt-in).

Wraps the upstream stablematerials_image2pbr.py invocation cleanly.
SM lives in mesa-env (cu130 + diffusers), so we shell out to its
python and then rename the outputs to W4 canonical names.

Per the audit: SM is NOT the W4 default any more. It's opt-in via
`--pbr-backend sm`. SM is good for rock-class slots with rich micro-
detail; bad for snow / soft / organic where it invents detail that
disagrees with the albedo.

Native res for SM is 512. Larger sizes LANCZOS-stretch the output;
not worth the lie. We always run SM at 512 then upsample to match
the albedo size at the caller's level if needed.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

SM_PYTHON = r"D:\assets\animators\mesa-env\venv\Scripts\python.exe"
SM_SCRIPT = r"D:\assets\pipelines\textures\stablematerials_image2pbr.py"

# Which SM outputs map to which W4 canonical names.
SM_MAP_NAMES = ("albedo", "normal", "roughness", "ao", "height", "metallic")


def derive_pbr(albedo_path: Path, out_dir: Path, *, mode: str = "standard",
               size: int = 512) -> dict:
    """Run StableMaterials over an albedo, copy outputs into out_dir
    with canonical names.

    Returns a log dict on success. Raises RuntimeError on failure (caller
    chooses fallback strategy).
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    sm_tmp = Path(tempfile.mkdtemp(prefix="tx_sm_"))
    try:
        cmd = [
            SM_PYTHON, SM_SCRIPT,
            "--input", str(albedo_path),
            "--out", str(sm_tmp),
            "--id", "sm_out",
            "--mode", mode,
            "--size", str(size),
        ]
        print(f"[tx_pbr_sm] running SM (mode={mode}, size={size})")
        result = subprocess.run(cmd, capture_output=False)
        if result.returncode != 0:
            raise RuntimeError(f"StableMaterials failed rc={result.returncode}")
        # SM produces <id>_<map>.png; rename to canonical map.png in out_dir
        for m in SM_MAP_NAMES:
            sp = sm_tmp / f"sm_out_{m}.png"
            if sp.exists():
                shutil.copy2(sp, out_dir / f"{m}.png")
        # Always copy the source albedo unmodified
        if not (out_dir / "albedo.png").exists():
            shutil.copy2(albedo_path, out_dir / "albedo.png")
        present = [m for m in SM_MAP_NAMES if (out_dir / f"{m}.png").exists()]
        return {
            "backend": "tx_pbr_sm",
            "mode": mode,
            "size": size,
            "maps": present,
        }
    finally:
        shutil.rmtree(sm_tmp, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--albedo", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--mode", default="standard")
    ap.add_argument("--size", type=int, default=512)
    args = ap.parse_args()
    log = derive_pbr(args.albedo, args.out, mode=args.mode, size=args.size)
    print(json.dumps(log, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
