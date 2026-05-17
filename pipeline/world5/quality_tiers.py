"""W5 quality tiers — Python mirror of engine/scripts/core/QualityTiers.gd.

Per spec 13. Reads engine/resources/quality_tiers.json. Provides
load + get + get_current + names. Used by pipeline-side tools that
need per-tier knobs (texture pipeline output sizes, LOD bake
resolutions, decoration density, etc.).

Cross-impl parity: tests/test_quality_tiers_cross_impl.py exercises
this module against the GDScript resolver to ensure both return
identical dicts for any tier.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from world5.log import log

SYSTEM_NAME = "quality_tiers"

_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_CONFIG_PATH = _REPO_ROOT / "engine" / "resources" / "quality_tiers.json"

# Tier names locked per spec 13 (post-audit S7: ultra_far → cinematic)
TIER_NAMES = ("low", "medium", "high", "ultra", "cinematic")
DEFAULT_TIER = "high"

_cache: dict[str, dict] | None = None
_cache_path: Path | None = None


class QualityTiers:
    """Static class — load once, query many. Mirrors GDScript shape."""

    @staticmethod
    def load(config_path: Path | None = None) -> dict[str, dict]:
        """Load + parse quality_tiers.json. Cached for subsequent calls
        with the same path."""
        global _cache, _cache_path
        path = config_path or _DEFAULT_CONFIG_PATH
        if _cache is not None and _cache_path == path:
            return _cache
        if not path.exists():
            log.error(SYSTEM_NAME, "config not found", path=str(path))
            raise FileNotFoundError(f"quality_tiers.json not found at {path}")
        with path.open(encoding="utf-8") as f:
            data = json.load(f)
        if "tiers" not in data:
            log.error(SYSTEM_NAME, "config missing 'tiers' key", path=str(path))
            raise ValueError("quality_tiers.json must have 'tiers' top-level key")
        _cache = data["tiers"]
        _cache_path = path
        # Sanity: every named tier exists in config
        missing = [t for t in TIER_NAMES if t not in _cache]
        if missing:
            log.warn(SYSTEM_NAME, "tier names missing from config", missing=missing)
        return _cache

    @staticmethod
    def get(tier_name: str) -> dict:
        """Return the dict for `tier_name`. Loads config on first call.

        Raises KeyError if tier_name is unknown.
        """
        tiers = QualityTiers.load()
        if tier_name not in tiers:
            log.error(SYSTEM_NAME, "unknown tier", tier=tier_name,
                      available=list(tiers.keys()))
            raise KeyError(f"Unknown tier: {tier_name}")
        return tiers[tier_name]

    @staticmethod
    def get_current() -> dict:
        """Return the current tier per env var WORLD5_QUALITY_TIER (or default)."""
        tier = os.environ.get("WORLD5_QUALITY_TIER", DEFAULT_TIER)
        if tier not in TIER_NAMES:
            log.warn(SYSTEM_NAME, "invalid WORLD5_QUALITY_TIER; falling back to default",
                     env_tier=tier, default=DEFAULT_TIER)
            tier = DEFAULT_TIER
        return QualityTiers.get(tier)

    @staticmethod
    def names() -> list[str]:
        """Return the list of known tier names."""
        return list(TIER_NAMES)

    @staticmethod
    def _reset_cache() -> None:
        """Test helper: clear the cache so load() re-reads from disk."""
        global _cache, _cache_path
        _cache = None
        _cache_path = None
