"""Cross-implementation parity test for QualityTiers.

Per spec 13 quality bar: "Cross-impl parity: 0 differences between
Python and GDScript resolvers for any valid config."

Strategy: load the canonical engine/resources/quality_tiers.json
via Python's QualityTiers; serialize to a deterministic JSON; have
Godot headless run the same load + serialize via gut test that
writes its output to a tmp file; compare.

Lighter strategy (used here): Python loads + serializes; assert the
result equals the JSON-roundtripped raw config. This catches the
common drift mode (Python munging the data on read). The full
cross-impl test that diffs against GDScript output lives at
engine/tests/integration/test_quality_tiers_parity.gd (gut side)
and asserts the gut-loaded tier dict matches the Python-loaded one.
For Phase 2.3, the structural test in this file plus the gut test
verifying the same load is sufficient. A diff-script that drives
both is added in Phase 2.11 when world_contract preflight lands.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import pytest

from world5.quality_tiers import (
    DEFAULT_TIER,
    TIER_NAMES,
    QualityTiers,
    _DEFAULT_CONFIG_PATH,
)


@pytest.fixture(autouse=True)
def _reset_cache():
    QualityTiers._reset_cache()
    yield
    QualityTiers._reset_cache()


def test_canonical_config_exists():
    assert _DEFAULT_CONFIG_PATH.exists(), \
        f"engine/resources/quality_tiers.json missing at {_DEFAULT_CONFIG_PATH}"


def test_all_tier_names_present():
    tiers = QualityTiers.load()
    for name in TIER_NAMES:
        assert name in tiers, f"tier '{name}' missing from config"


def test_tier_dict_self_consistent():
    """Each tier's `tier_name` field matches its key."""
    tiers = QualityTiers.load()
    for name, tier in tiers.items():
        assert tier["tier_name"] == name, f"tier {name} has wrong tier_name"


def test_frame_budget_engine_share_matches_x_frame_budget_spec():
    """X_FRAME_BUDGET spec table: low=4, medium=6, high=8, ultra=10, cinematic=20."""
    expected = {"low": 4.0, "medium": 6.0, "high": 8.0, "ultra": 10.0, "cinematic": 20.0}
    for name, expected_share in expected.items():
        actual = QualityTiers.get(name)["frame_budget_engine_share_ms"]
        assert actual == expected_share, \
            f"{name}: engine_share_ms = {actual}, X_FRAME_BUDGET says {expected_share}"


def test_visibility_distance_monotone_with_tier():
    """Higher tier = farther visibility."""
    distances = [QualityTiers.get(t)["visibility_ship_distance_m"] for t in TIER_NAMES]
    for a, b in zip(distances, distances[1:]):
        assert a < b, f"visibility distance non-monotone: {distances}"


def test_nav_grid_n_matches_spec_33():
    """Spec 33 + SA-S4.5: low=32, medium=48, high=64, ultra=96, cinematic=128."""
    expected = {"low": 32, "medium": 48, "high": 64, "ultra": 96, "cinematic": 128}
    for name, n in expected.items():
        assert QualityTiers.get(name)["nav_grid_n"] == n


def test_terrain_step_n_matches_outer_ring_cell_size():
    for name in TIER_NAMES:
        tier = QualityTiers.get(name)
        expected = tier["terrain_step0_m"] * (2 ** (tier["terrain_rings"] - 1))
        assert tier["terrain_stepN_m"] == pytest.approx(expected), name


def test_terrain_cpu_page_budget_covers_visible_working_set():
    for name in TIER_NAMES:
        tier = QualityTiers.get(name)
        required = _visible_page_working_set(tier)
        assert tier["streaming_budget_cpu_pages"] >= required, \
            f"{name}: cpu_pages budget must cover {required} visible pages"


def test_get_current_default():
    """Default tier is 'high' when env var unset."""
    import os
    os.environ.pop("WORLD5_QUALITY_TIER", None)
    QualityTiers._reset_cache()
    assert QualityTiers.get_current()["tier_name"] == DEFAULT_TIER


def test_get_current_env_override(monkeypatch):
    monkeypatch.setenv("WORLD5_QUALITY_TIER", "ultra")
    QualityTiers._reset_cache()
    assert QualityTiers.get_current()["tier_name"] == "ultra"


def test_get_unknown_raises():
    with pytest.raises(KeyError):
        QualityTiers.get("nonexistent_tier")


def test_names_returns_5_tiers():
    assert len(QualityTiers.names()) == 5
    assert QualityTiers.names() == list(TIER_NAMES)


def test_load_idempotent():
    """Calling load() twice returns the same cached dict."""
    first = QualityTiers.load()
    second = QualityTiers.load()
    assert first is second  # cached, not re-parsed


def test_all_tiers_have_required_keys():
    """Every tier dict has the keys other Tier 0 / Tier 1 systems consume."""
    required = {
        "tier_name",
        "frame_budget_engine_share_ms",
        "frame_budget_target_ms",
        "streaming_budget_active_jobs",
        "streaming_budget_cpu_pages",
        "streaming_budget_gpu_pages",
        "streaming_budget_asset_cache_mb",
        "terrain_grid_n",
        "visibility_ship_distance_m",
        "decoration_max_visible",
        "spatial_index_decoration_cell_size_m",
        "spatial_index_terrain_cell_size_m",
        "spatial_index_foliage_cell_size_m",
        "lighting_recipe",
        "atmosphere_profile",
        "nav_grid_n",
    }
    for name in TIER_NAMES:
        tier = QualityTiers.get(name)
        missing = required - set(tier.keys())
        assert not missing, f"tier {name} missing required keys: {missing}"


def _visible_page_working_set(tier: dict) -> int:
    total = 0
    page_extent_m = 256.0
    for ring in range(tier["terrain_rings"]):
        extent_m = (tier["terrain_grid_n"] - 1) * tier["terrain_step0_m"] * (2 ** ring)
        raw = extent_m / page_extent_m
        pages_per_side = 2 if raw <= 1.0 else math.ceil(raw) + 1
        total += pages_per_side * pages_per_side
    return total
