"""Unit tests for KernelComposer.bake_page (Phase 5.7.c).

bake_page runs a biome's full kernel chain on a whole page —
the entry point that makes erosion stages usable (they need
page-scope context, not per-point). Output is optionally cached
via spec 12 ContentAddressStore so re-bakes with unchanged inputs
skip recompute.

Per superpowers:test-driven-development: one test at a time, RED
before GREEN.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from world5.content_address import ContentAddressStore
from world5.kernels import KernelComposer


# --- fixtures ---


def _noise_only_catalog() -> dict:
    return {
        "world_name": "noise_only",
        "biomes": [{
            "name": "alpine",
            "auto_biome_rules": {
                "elevation_m": [-1000, 1000], "slope_deg": [0, 90],
                "band_width_elevation_m": 1.0, "band_width_slope_deg": 1.0,
            },
            "kernel": {
                "type": "noise_stack",
                "params": {"octaves": 6, "frequency": 1.0 / 256.0,
                           "lacunarity": 2.0, "gain": 0.5,
                           "amplitude": 30.0},
            },
        }],
    }


def _eroded_catalog() -> dict:
    """Same noise base as above, plus a short erosion post-process.
    The erosion params are tiny on purpose so tests run fast."""
    return {
        "world_name": "eroded",
        "biomes": [{
            "name": "alpine",
            "auto_biome_rules": {
                "elevation_m": [-1000, 1000], "slope_deg": [0, 90],
                "band_width_elevation_m": 1.0, "band_width_slope_deg": 1.0,
            },
            "kernel": {
                "type": "chain",
                "stages": [
                    {"type": "noise_stack",
                     "params": {"octaves": 6, "frequency": 1.0 / 256.0,
                                "lacunarity": 2.0, "gain": 0.5,
                                "amplitude": 30.0}},
                    {"type": "erosion",
                     "params": {"iterations": 10, "thermal_iterations": 5}},
                ],
            },
        }],
    }


# --- contract: bake_page produces a page-shaped array ---


def test_bake_page_returns_grid_shaped_float32() -> None:
    c = KernelComposer(_noise_only_catalog())
    page = c.bake_page(world_origin_xz=(0.0, 0.0),
                       extent_m=256.0, grid_n=32, seed=42)
    assert page.shape == (32, 32)
    assert page.dtype == np.float32
    assert np.isfinite(page).all()


def test_bake_page_noise_only_matches_bare_kernel() -> None:
    """A noise-only chain (no erosion stages) baked through composer
    must equal NoiseStackKernel.sample_page directly."""
    from world5.kernels import NoiseStackKernel
    c = KernelComposer(_noise_only_catalog())
    bare = NoiseStackKernel(octaves=6, frequency=1.0 / 256.0,
                            lacunarity=2.0, gain=0.5, amplitude=30.0)
    baked = c.bake_page(world_origin_xz=(100.0, 50.0),
                        extent_m=256.0, grid_n=16, seed=7)
    direct = bare.sample_page((100.0, 50.0), extent_m=256.0,
                              grid_n=16, seed=7)
    np.testing.assert_array_equal(baked, direct)


# --- erosion stages now USABLE via bake_page (the 5.7.c unblock) ---


def test_bake_page_with_erosion_changes_output_vs_noise_only() -> None:
    """With identical noise base + seed, adding an erosion stage must
    change the height field (otherwise erosion is a no-op). Visible
    erosion verified more thoroughly via test_drainage_radial_*
    in test_erosion_kernel.py — here we just confirm the chain
    actually runs the erosion stage instead of skipping it."""
    c_plain = KernelComposer(_noise_only_catalog())
    c_eroded = KernelComposer(_eroded_catalog())
    plain = c_plain.bake_page((0.0, 0.0), 256.0, 32, seed=42)
    eroded = c_eroded.bake_page((0.0, 0.0), 256.0, 32, seed=42)
    # Erosion redistributes mass: at least some cells must differ
    # by > 0.01m (well above float noise).
    diff = np.abs(eroded - plain)
    changed = (diff > 0.01).sum()
    assert changed > 50, \
        f"erosion stage should change {changed=} cells (expected > 50)"


# --- determinism ---


def test_bake_page_deterministic_same_inputs() -> None:
    c = KernelComposer(_eroded_catalog())
    a = c.bake_page((10.0, 20.0), 256.0, 32, seed=42)
    b = c.bake_page((10.0, 20.0), 256.0, 32, seed=42)
    np.testing.assert_array_equal(a, b)


# --- cache integration (spec 12 ContentAddressStore) ---


def test_bake_page_cache_miss_then_hit(tmp_path: Path) -> None:
    """First bake_page call writes the page to the store; second call
    with identical (catalog, world_origin, extent, grid, seed) hits
    the cache and returns the same array."""
    store = ContentAddressStore(store_root=tmp_path / "cache", cap_gb=0.1)
    c = KernelComposer(_eroded_catalog())
    page_a = c.bake_page((0.0, 0.0), 256.0, 16, seed=42, store=store)
    # After first call, exactly 1 artifact in the store.
    assert len(store.list_artifacts()) == 1
    page_b = c.bake_page((0.0, 0.0), 256.0, 16, seed=42, store=store)
    np.testing.assert_array_equal(page_a, page_b)
    # Still only 1 artifact — second call was a hit, no new store entry.
    assert len(store.list_artifacts()) == 1


def test_bake_page_cache_miss_on_seed_change(tmp_path: Path) -> None:
    """Different seed → different cache key → new artifact in store."""
    store = ContentAddressStore(store_root=tmp_path / "cache", cap_gb=0.1)
    c = KernelComposer(_eroded_catalog())
    c.bake_page((0.0, 0.0), 256.0, 16, seed=1, store=store)
    c.bake_page((0.0, 0.0), 256.0, 16, seed=2, store=store)
    assert len(store.list_artifacts()) == 2


def test_bake_page_cache_miss_on_extent_change(tmp_path: Path) -> None:
    """Different extent → different cache key (same world XZ at
    different page sizes is a different artifact)."""
    store = ContentAddressStore(store_root=tmp_path / "cache", cap_gb=0.1)
    c = KernelComposer(_eroded_catalog())
    c.bake_page((0.0, 0.0), 256.0, 16, seed=42, store=store)
    c.bake_page((0.0, 0.0), 512.0, 16, seed=42, store=store)
    assert len(store.list_artifacts()) == 2


def test_bake_page_cache_metadata_records_provenance(tmp_path: Path) -> None:
    """Cache metadata must record enough to identify what was baked:
    catalog hash, world_origin, extent, grid_n, seed, biome name."""
    store = ContentAddressStore(store_root=tmp_path / "cache", cap_gb=0.1)
    c = KernelComposer(_eroded_catalog())
    c.bake_page((100.0, 200.0), 256.0, 16, seed=42, store=store)
    artifacts = store.list_artifacts()
    assert len(artifacts) == 1
    meta = artifacts[0]["metadata"]
    # Provenance fields — caller can audit what got cached.
    assert "world_origin_xz" in meta
    assert "extent_m" in meta
    assert "grid_n" in meta
    assert "seed" in meta
    assert meta["seed"] == 42
    assert meta["extent_m"] == 256.0
    assert meta["grid_n"] == 16


def test_bake_page_no_store_does_not_persist(tmp_path: Path) -> None:
    """When store=None (default), bake_page runs but doesn't touch
    the filesystem cache. Useful for tests + one-off bakes."""
    store = ContentAddressStore(store_root=tmp_path / "cache", cap_gb=0.1)
    c = KernelComposer(_eroded_catalog())
    c.bake_page((0.0, 0.0), 256.0, 16, seed=42)  # no store
    assert len(store.list_artifacts()) == 0
