"""W5 version + semver helpers — Python mirror of engine/scripts/core/World5.gd.

Per spec 17. Reads version from engine/plugin.cfg at import time.
Provides parse + is_compatible + needs_migration + migration_path
helpers used by every artifact loader checking version stamps.
"""

from __future__ import annotations

import re
from pathlib import Path

from world5.log import log

SYSTEM_NAME = "world5"

_PLUGIN_CFG = Path(__file__).resolve().parents[2] / "engine" / "plugin.cfg"


def _read_version_from_plugin_cfg() -> str:
    """Parse `version="X.Y.Z"` out of engine/plugin.cfg."""
    if not _PLUGIN_CFG.exists():
        log.warn(SYSTEM_NAME, "plugin.cfg not found; using fallback version 0.0.0",
                 path=str(_PLUGIN_CFG))
        return "0.0.0"
    text = _PLUGIN_CFG.read_text(encoding="utf-8")
    match = re.search(r'^\s*version\s*=\s*"([^"]+)"', text, re.MULTILINE)
    if not match:
        log.warn(SYSTEM_NAME, "No version field in plugin.cfg; using fallback 0.0.0")
        return "0.0.0"
    return match.group(1)


WORLD5_VERSION: str = _read_version_from_plugin_cfg()


def parse(version_str: str) -> tuple[int, int, int]:
    """Parse a semver string into (major, minor, patch) tuple.

    Returns (0, 0, 0) on invalid input + logs warning. Pre-release
    suffixes (e.g. '0.1.0-beta.1') are stripped; the numeric components
    are returned.
    """
    parts = version_str.split(".")
    if len(parts) < 3:
        log.warn(SYSTEM_NAME, "Invalid version string", version=version_str)
        return (0, 0, 0)
    nums: list[int] = []
    for p in parts[:3]:
        num_str = p.split("-")[0]
        if not num_str.isdigit():
            log.warn(SYSTEM_NAME, "Invalid version component",
                     version=version_str, component=p)
            return (0, 0, 0)
        nums.append(int(num_str))
    return (nums[0], nums[1], nums[2])


def is_compatible(artifact_version: str, runtime_version: str | None = None) -> bool:
    """Returns True if artifact_version can be loaded by runtime_version.

    Compat rules per spec 17:
    - Same MAJOR → compatible
    - Different MAJOR → not compatible; migration required
    - Pre-1.0 (MAJOR==0): MINOR differences also break
    """
    if runtime_version is None:
        runtime_version = WORLD5_VERSION
    rt = parse(runtime_version)
    art = parse(artifact_version)
    if rt[0] != art[0]:
        return False
    if rt[0] == 0 and rt[1] != art[1]:
        return False
    return True


def needs_migration(artifact_version: str, runtime_version: str | None = None) -> bool:
    """Returns True if artifact_version requires migration to load."""
    return not is_compatible(artifact_version, runtime_version)


def migration_path(from_v: str, to_v: str) -> list[str]:
    """Returns the chain of intermediate versions for from_v → to_v.

    Stub for Phase 2.2: returns [to_v] (direct migration). Real
    implementation walks `pipeline/migrations/` in Phase 14.
    """
    if from_v == to_v:
        return []
    return [to_v]
