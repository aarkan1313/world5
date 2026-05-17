"""W5 verify CLI — tiered test runner per spec 06.

Tiers:
- --fastest: pytest only, target ≤ 15s (dev tight loop)
- --fast:    pytest + gut (Godot headless), target ≤ 90s (batch dev)
- default:   above + preflight checks, target ≤ 3 min (pre-commit)
- --full:    above + capture-based renderer tests, target ≤ 15 min (CI / release)

Exit codes (per spec 06):
- 0: all clear
- 1: test failure
- 2: preflight failure
- 3: environment error (Godot not found, gut missing, etc.)
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]


class VerifyMode(str, Enum):
    FASTEST = "fastest"
    FAST = "fast"
    DEFAULT = "default"
    FULL = "full"


@dataclass
class LayerResult:
    name: str
    status: str  # "pass", "fail", "skip", "error"
    duration_s: float = 0.0
    details: dict = field(default_factory=dict)


@dataclass
class VerifyResult:
    mode: VerifyMode
    started_at: str
    duration_s: float
    layers: list[LayerResult]
    overall_status: str  # "pass", "fail", "error"
    exit_code: int

    def to_dict(self) -> dict:
        return {
            "version": 1,
            "mode": self.mode.value,
            "started_at": self.started_at,
            "duration_s": round(self.duration_s, 2),
            "layers": {
                layer.name: {
                    "status": layer.status,
                    "duration_s": round(layer.duration_s, 2),
                    **layer.details,
                }
                for layer in self.layers
            },
            "overall_status": self.overall_status,
            "exit_code": self.exit_code,
        }


def _run_pytest() -> LayerResult:
    """Run pytest from repo root. Returns LayerResult."""
    start = time.monotonic()
    cmd = [sys.executable, "-m", "pytest", "-q", str(REPO_ROOT / "tests")]
    # Also include pipeline tests if they exist
    pipeline_tests = list((REPO_ROOT / "pipeline").rglob("test_*.py"))
    if pipeline_tests:
        cmd.append(str(REPO_ROOT / "pipeline"))
    try:
        proc = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        return LayerResult(
            name="pytest",
            status="error",
            duration_s=time.monotonic() - start,
            details={"error": "timeout"},
        )

    duration = time.monotonic() - start
    status = "pass" if proc.returncode == 0 else "fail"
    # Parse pytest's summary line (e.g. "5 passed in 0.12s")
    last_lines = proc.stdout.strip().split("\n")[-5:]
    summary = next(
        (line for line in reversed(last_lines) if "passed" in line or "failed" in line or "error" in line),
        "",
    )
    return LayerResult(
        name="pytest",
        status=status,
        duration_s=duration,
        details={"returncode": proc.returncode, "summary": summary.strip()},
    )


def _resolve_godot_bin() -> Path | None:
    """Locate the Godot binary for gut runs (SA2-C1.2).

    Order of preference:
    1. WORLD5_GODOT_BIN env var (explicit override)
    2. `godot` on PATH (Unix convention)
    3. C:/Godot/Godot_v4.5-stable_win64.exe (this dev's Windows install)

    Returns None if Godot cannot be located; gut layer skips with a
    clear reason in that case.
    """
    import os
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


def _run_gut(real_gpu: bool = False) -> LayerResult:
    """Run gut. Returns LayerResult.

    Phase 2.5+: gut runs in headless mode for the bulk of tests.
    Real GPU tests (test_gpu_real_device.gd etc.) require a real
    RenderingDevice, which headless mode disables. When real_gpu=True
    we relaunch with --display-driver windows --rendering-driver vulkan
    and only run tests in the integration/ dir matching pattern
    test_*_real_device.gd or test_*_gpu.gd.
    """
    start = time.monotonic()
    gut_path = REPO_ROOT / "demo" / "addons" / "gut"
    name = "gut_real_gpu" if real_gpu else "gut"
    if not gut_path.exists():
        return LayerResult(
            name=name,
            status="skip",
            duration_s=time.monotonic() - start,
            details={"reason": "gut not installed at demo/addons/gut/"},
        )
    godot_path = _resolve_godot_bin()
    if godot_path is None:
        return LayerResult(
            name=name,
            status="skip",
            duration_s=time.monotonic() - start,
            details={
                "reason": "Godot binary not found",
                "hint": "Set WORLD5_GODOT_BIN env var, OR add `godot` to PATH, OR install Godot 4.5 at C:/Godot/",
            },
        )
    godot_bin = str(godot_path)
    if real_gpu:
        cmd = [
            godot_bin,
            "--display-driver", "windows",
            "--rendering-driver", "vulkan",
            "--path", str(REPO_ROOT / "demo"),
            "--script", "res://addons/gut/gut_cmdln.gd",
            "-gdir=res://addons/world5/tests/",
            "-ginclude_subdirs",
            "-gprefix=test_",
            "-gsuffix=_real_device.gd",
            "-gexit",
        ]
    else:
        cmd = [
            godot_bin,
            "--headless",
            "--path", str(REPO_ROOT / "demo"),
            "--script", "res://addons/gut/gut_cmdln.gd",
            "-gdir=res://addons/world5/tests/",
            "-ginclude_subdirs",
            "-gexit",
        ]
    try:
        proc = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return LayerResult(
            name="gut",
            status="error",
            duration_s=time.monotonic() - start,
            details={"reason": "godot timeout"},
        )
    duration = time.monotonic() - start
    status = "pass" if proc.returncode == 0 else "fail"
    return LayerResult(
        name=name,
        status=status,
        duration_s=duration,
        details={"returncode": proc.returncode},
    )


def _run_preflight() -> LayerResult:
    """Run world_contract preflight (allowlist, doc_health, logging_lint)."""
    from world5.world_contract import validate
    start = time.monotonic()
    result = validate()
    duration = time.monotonic() - start
    status = "pass" if result.passed else "fail"
    return LayerResult(
        name="preflight",
        status=status,
        duration_s=duration,
        details={
            "errors": len(result.errors),
            "warnings": len(result.warnings),
        },
    )


def _run_capture() -> LayerResult:
    """Run capture-based renderer tests.

    Stub for Phase 2.1: capture tests land alongside the first
    renderer scenes (Phase 4 terrain MVP). Until then this layer
    skips with a clear message.
    """
    return LayerResult(
        name="capture",
        status="skip",
        details={"reason": "capture tests land in Phase 4 (terrain MVP)"},
    )


def run_verify(mode: VerifyMode = VerifyMode.DEFAULT) -> VerifyResult:
    """Run the verify pipeline for the given mode."""
    start = time.monotonic()
    started_at = time.strftime("%Y-%m-%dT%H:%M:%S")
    layers: list[LayerResult] = []

    # Layer 1: pytest (always run, all modes)
    layers.append(_run_pytest())

    # Layer 2: gut headless (fast / default / full)
    if mode in (VerifyMode.FAST, VerifyMode.DEFAULT, VerifyMode.FULL):
        layers.append(_run_gut(real_gpu=False))

    # Layer 3: gut real GPU (full only — opens a Vulkan window, needs GPU)
    if mode == VerifyMode.FULL:
        layers.append(_run_gut(real_gpu=True))

    # Layer 4: preflight (default / full)
    if mode in (VerifyMode.DEFAULT, VerifyMode.FULL):
        layers.append(_run_preflight())

    # Layer 5: capture-based renderer tests (full only)
    if mode == VerifyMode.FULL:
        layers.append(_run_capture())

    duration = time.monotonic() - start

    # Aggregate verdict
    has_fail = any(layer.status == "fail" for layer in layers)
    has_error = any(layer.status == "error" for layer in layers)
    if has_error:
        overall = "error"
        exit_code = 3
    elif has_fail:
        overall = "fail"
        # Pytest fail = exit 1; preflight fail = exit 2
        pytest_failed = any(
            layer.name == "pytest" and layer.status == "fail" for layer in layers
        )
        exit_code = 1 if pytest_failed else 2
    else:
        overall = "pass"
        exit_code = 0

    return VerifyResult(
        mode=mode,
        started_at=started_at,
        duration_s=duration,
        layers=layers,
        overall_status=overall,
        exit_code=exit_code,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="world5.verify",
        description="W5 tiered test runner per spec 06.",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--fastest", action="store_const", dest="mode", const=VerifyMode.FASTEST)
    group.add_argument("--fast", action="store_const", dest="mode", const=VerifyMode.FAST)
    group.add_argument("--full", action="store_const", dest="mode", const=VerifyMode.FULL)
    parser.add_argument("--json", action="store_true", help="Output JSON summary")
    args = parser.parse_args(argv)

    mode = args.mode or VerifyMode.DEFAULT
    result = run_verify(mode)

    if args.json:
        print(json.dumps(result.to_dict(), indent=2))
    else:
        # ASCII-only markers — Windows console default cp1252 can't encode
        # ✓/✗ glyphs without explicit utf-8 mode.
        print(f"W5 verify ({mode.value}) -- {result.overall_status} in {result.duration_s:.1f}s")
        for layer in result.layers:
            status_marker = {"pass": "OK", "fail": "FAIL", "error": "ERR", "skip": "skip"}[layer.status]
            print(
                f"  [{status_marker:>4}] {layer.name:<10} "
                f"{layer.duration_s:>5.1f}s  {layer.details}"
            )

    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
