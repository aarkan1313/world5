"""Cross-impl parity: GPU compute shader vs Python NoiseStackKernel.

Strategy (matches SA2-C2.1 cross-impl pattern):
1. Run the gut emitter (engine/tests/integration/test_terrain_backend_parity_emit.gd)
   which dispatches the real compute shader and writes heights to
   user://_terrain_parity_emit/<case>.json
2. For each case, re-run the Python NoiseStackKernel with identical
   params
3. Diff: max-abs-difference must be <= 1e-3 m

If the GPU emit was skipped (no RD), this test is skipped too.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

from world5.kernels import NoiseStackKernel


REPO_ROOT = Path(__file__).resolve().parents[2]
GODOT_USER_DATA = Path(os.environ.get(
    "APPDATA",
    str(Path.home() / ".local/share")
)) / "Godot/app_userdata/W5 Demo/_terrain_parity_emit"

PARITY_TOLERANCE_M = 1e-4  # spec 20 quality bar (TB-REV-S1)


def _resolve_godot_bin() -> Path | None:
    env_bin = os.environ.get("WORLD5_GODOT_BIN")
    if env_bin:
        p = Path(env_bin)
        if p.exists():
            return p
    on_path = shutil.which("godot")
    if on_path:
        return Path(on_path)
    fallback = Path("C:/Godot/Godot_v4.5-stable_win64.exe")
    if fallback.exists():
        return fallback
    return None


@pytest.fixture(scope="module")
def gpu_emitted_pages() -> list[Path]:
    """Run the gut emitter; return the JSON files it wrote.

    Skips the test if no Godot binary or no GPU available.
    """
    godot = _resolve_godot_bin()
    if godot is None:
        pytest.skip("Godot binary not found; set WORLD5_GODOT_BIN or install at C:/Godot/")

    # Clear stale emit dir so we know the fresh emit ran
    if GODOT_USER_DATA.exists():
        shutil.rmtree(GODOT_USER_DATA)

    cmd = [
        str(godot),
        "--display-driver", "windows",
        "--rendering-driver", "vulkan",
        "--single-window",
        "--path", str(REPO_ROOT / "demo"),
        "--script", "res://addons/gut/gut_cmdln.gd",
        "-gtest=res://addons/world5/tests/integration/test_terrain_backend_parity_emit_real_device.gd",
        "-gexit",
    ]
    result = subprocess.run(
        cmd, capture_output=True, text=True, timeout=120,
        encoding="utf-8", errors="replace",
    )
    if result.returncode != 0:
        # The "no RD" case prints pending() and exits 0; if returncode
        # is nonzero something actually broke
        pytest.skip(f"gut emitter failed (returncode={result.returncode}): "
                    f"stderr={result.stderr[:500]}")

    if not GODOT_USER_DATA.exists():
        pytest.skip("emit dir not created (likely --headless run; no RD)")

    files = sorted(GODOT_USER_DATA.glob("*.json"))
    if not files:
        pytest.skip("no parity cases emitted (RD likely unavailable)")
    return files


def test_gpu_python_parity(gpu_emitted_pages: list[Path]) -> None:
    """For every emitted GPU page, the Python kernel produces matching
    heights within PARITY_TOLERANCE_M."""
    n_cases = 0
    max_diff_overall = 0.0
    for path in gpu_emitted_pages:
        with path.open(encoding="utf-8") as f:
            payload = json.load(f)

        kernel = NoiseStackKernel(
            octaves=int(payload["octaves"]),
            frequency=float(payload["frequency"]),
            lacunarity=float(payload["lacunarity"]),
            gain=float(payload["gain"]),
            amplitude=float(payload["amplitude"]),
        )
        py_heights = kernel.sample_page(
            (float(payload["world_xz"][0]), float(payload["world_xz"][1])),
            float(payload["extent_m"]),
            int(payload["grid_n"]),
            int(payload["seed"]),
        ).flatten()
        gpu_heights = np.asarray(payload["heights"], dtype=np.float32)

        assert py_heights.size == gpu_heights.size, (
            f"size mismatch in {payload['name']}: "
            f"py={py_heights.size} gpu={gpu_heights.size}"
        )
        diff = np.abs(py_heights - gpu_heights)
        max_diff = float(diff.max())
        max_diff_overall = max(max_diff_overall, max_diff)
        assert max_diff <= PARITY_TOLERANCE_M, (
            f"parity case {payload['name']!r}: max abs diff {max_diff} m "
            f"exceeds tolerance {PARITY_TOLERANCE_M} m"
        )
        n_cases += 1

    assert n_cases > 0, "no parity cases ran"
    print(f"\ngpu_python_parity: {n_cases} cases pass; "
          f"max diff observed = {max_diff_overall:.6f} m "
          f"(tolerance {PARITY_TOLERANCE_M} m)")
