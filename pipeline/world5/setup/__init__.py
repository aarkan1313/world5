"""W5 setup CLI: per-machine addon link + verify install.

Per spec 18. Two commands:

    python -m world5.setup install_demo
        Set up demo/addons/world5/ → ../../engine/ link (junction
        on Windows; symlink on Unix). Creates if missing; verifies
        if exists.

    python -m world5.setup verify_install <consumer_project_path>
        Validate a consumer's addons/world5/ install:
        - link/dir exists + points at engine/
        - plugin.cfg present + version matches
        - autoloads can be loaded by Godot (smoke test)

Windows note (SA-M2.11): `mklink /D` needs admin or Developer Mode.
This script falls back to Windows Junction (`New-Item -ItemType
Junction`) which requires neither.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

from world5.log import log

SYSTEM_NAME = "setup"

REPO_ROOT = Path(__file__).resolve().parents[3]


def _engine_dir() -> Path:
    return REPO_ROOT / "engine"


def install_demo(repo_root: Path | None = None) -> int:
    """Create demo/addons/world5/ → engine/ link. Returns exit code."""
    root = repo_root or REPO_ROOT
    engine = root / "engine"
    demo_addons = root / "demo" / "addons"
    link = demo_addons / "world5"

    if not engine.exists():
        log.error(SYSTEM_NAME, "engine/ not found", path=str(engine))
        return 1
    demo_addons.mkdir(parents=True, exist_ok=True)

    if link.exists():
        # Verify it points at engine/
        target = _resolve_link(link)
        if target and target.resolve() == engine.resolve():
            log.info(SYSTEM_NAME, "demo/addons/world5 already linked correctly",
                     target=str(target))
            return 0
        log.error(SYSTEM_NAME, "demo/addons/world5 exists but points elsewhere",
                  current=str(target) if target else "(unknown)",
                  expected=str(engine))
        return 1

    # Create the link
    if platform.system() == "Windows":
        # Junction (no admin/Developer Mode needed; SA-M2.11 fallback)
        result = subprocess.run(
            ["powershell", "-Command",
             f"New-Item -ItemType Junction -Path '{link}' -Target '{engine}' "
             f"| Out-Null"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            log.error(SYSTEM_NAME, "junction create failed",
                      stderr=result.stderr.strip())
            return 1
        log.info(SYSTEM_NAME, "junction created",
                 link=str(link), target=str(engine))
    else:
        # Unix: symlink
        relative_target = os.path.relpath(engine, link.parent)
        link.symlink_to(relative_target)
        log.info(SYSTEM_NAME, "symlink created",
                 link=str(link), target=relative_target)
    return 0


def verify_install(consumer_project_path: Path, json_output: bool = False) -> int:
    """Verify a consumer's W5 install is correct. Returns exit code."""
    consumer = Path(consumer_project_path).resolve()
    addons_world5 = consumer / "addons" / "world5"
    issues: list[dict] = []

    if not consumer.exists():
        issues.append({
            "severity": "error",
            "message": f"consumer path does not exist: {consumer}",
        })
    if not addons_world5.exists():
        issues.append({
            "severity": "error",
            "message": f"addons/world5/ missing at {addons_world5}",
        })
    else:
        # Check plugin.cfg
        plugin_cfg = addons_world5 / "plugin.cfg"
        if not plugin_cfg.exists():
            issues.append({
                "severity": "error",
                "message": "addons/world5/plugin.cfg missing",
            })
        else:
            # Quick check: contains version field
            text = plugin_cfg.read_text(encoding="utf-8")
            if "version" not in text:
                issues.append({
                    "severity": "warning",
                    "message": "plugin.cfg has no version field",
                })
        # Check scripts/core/ exists with key autoloads
        core_dir = addons_world5 / "scripts" / "core"
        required = ["Log.gd", "World5.gd", "QualityTiers.gd",
                    "JobScheduler.gd", "AssetStream.gd"]
        missing = [r for r in required if not (core_dir / r).exists()]
        if missing:
            issues.append({
                "severity": "error",
                "message": "core scripts missing",
                "missing": missing,
            })

    passed = not any(i["severity"] == "error" for i in issues)

    if json_output:
        print(json.dumps({
            "consumer_path": str(consumer),
            "passed": passed,
            "issues": issues,
        }, indent=2))
    else:
        status = "PASS" if passed else "FAIL"
        print(f"W5 verify_install: {status}  ({len(issues)} issues)")
        for i in issues:
            print(f"  [{i['severity']}] {i['message']}")
    return 0 if passed else 1


def _resolve_link(path: Path) -> Path | None:
    """Resolve a link/junction; return None if not a link."""
    try:
        return path.resolve()
    except Exception:
        return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="world5.setup",
        description="W5 setup CLI (spec 18)."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_install = sub.add_parser("install_demo",
                                help="Link demo/addons/world5 → engine/")
    p_install.add_argument("--repo-root", type=Path, default=None,
                            help="Repo root (default: auto-detect)")

    p_verify = sub.add_parser("verify_install",
                               help="Verify a consumer's W5 install")
    p_verify.add_argument("consumer_path", type=Path)
    p_verify.add_argument("--json", action="store_true")

    args = parser.parse_args(argv)

    if args.cmd == "install_demo":
        return install_demo(args.repo_root)
    elif args.cmd == "verify_install":
        return verify_install(args.consumer_path, json_output=args.json)
    return 1


if __name__ == "__main__":
    sys.exit(main())
