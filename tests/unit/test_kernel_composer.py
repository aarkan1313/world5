"""Unit tests for KernelComposer (Phase 5.7.b).

Spec 19 §"KernelComposer" + spec 22 §"Catalog schema". The composer
turns a biome catalog into a function over (x, z) -> (height,
biome_weights). Per-biome kernel chains run via stage dispatch
(noise_stack today; erosion lands when 5.7.c wires content-addressed
cache).

Per superpowers:test-driven-development: one test at a time, write
the test first, verify RED, then implement minimum to GREEN.

Walking_demo catalog provides the canonical multi-biome fixture:
- alpine: auto_biome_rules elev [10, 60] band 10 → owns mid-to-high
- forest: auto_biome_rules elev [-50, 10] band 10 → owns low-to-mid
- crossover band: elev 5-15m
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from world5.kernels import KernelComposer, NoiseStackKernel


# --- fixture loader ---


def _walking_demo_catalog() -> dict:
    p = (Path(__file__).resolve().parents[2]
         / "engine" / "worlds" / "walking_demo" / "biome_catalog.json")
    return json.loads(p.read_text(encoding="utf-8"))


# --- construct + basic API ---


def test_constructible_from_walking_demo_catalog() -> None:
    catalog = _walking_demo_catalog()
    c = KernelComposer(catalog)
    assert c.biome_count == 2
    assert set(c.biome_names) == {"alpine", "forest"}


def test_construct_rejects_catalog_with_no_biomes() -> None:
    with pytest.raises(ValueError, match="biomes"):
        KernelComposer({"world_name": "empty", "biomes": []})


def test_construct_rejects_missing_kernel_field() -> None:
    cat = {
        "world_name": "x",
        "biomes": [{
            "name": "a",
            "auto_biome_rules": {
                "elevation_m": [0, 10], "slope_deg": [0, 90],
                "band_width_elevation_m": 1.0, "band_width_slope_deg": 1.0,
            },
            # no kernel field
        }],
    }
    with pytest.raises(ValueError, match="kernel"):
        KernelComposer(cat)


# --- biome weights (the architecturally-important piece) ---


def test_biome_weights_sum_to_one_at_arbitrary_points() -> None:
    """Per spec 22 §biome_weights: softmax across biomes' auto_rules
    produces a probability distribution. Sum at any (x, z) must be 1
    (within float epsilon)."""
    c = KernelComposer(_walking_demo_catalog())
    # Sample a grid of (x, z); for each, weights must sum to 1.
    rng = np.random.default_rng(42)
    for _ in range(20):
        x = float(rng.uniform(-1000.0, 1000.0))
        z = float(rng.uniform(-1000.0, 1000.0))
        # Need a height + slope to evaluate auto_rules; supply both
        # from a representative sample.
        weights = c.biome_weights(x=x, z=z, elev_m=0.0, slope_deg=5.0)
        assert weights.shape == (2,)
        assert abs(float(weights.sum()) - 1.0) < 1e-5, \
            f"weights sum {float(weights.sum())} != 1 at ({x}, {z})"


def test_forest_dominates_low_elevation() -> None:
    """Forest auto_rules: elev [-50, 10] band 10. At elev -30 (well
    inside forest's range, far from crossover), forest weight should
    dominate (>= 0.9)."""
    c = KernelComposer(_walking_demo_catalog())
    weights = c.biome_weights(x=0.0, z=0.0, elev_m=-30.0, slope_deg=5.0)
    forest_idx = c.biome_names.index("forest")
    assert weights[forest_idx] >= 0.9, \
        f"forest weight at elev=-30 should dominate; got {weights[forest_idx]}"


def test_alpine_dominates_high_elevation() -> None:
    """Alpine auto_rules: elev [10, 60] band 10. At elev 40 (well
    inside alpine's range), alpine weight should dominate."""
    c = KernelComposer(_walking_demo_catalog())
    weights = c.biome_weights(x=0.0, z=0.0, elev_m=40.0, slope_deg=5.0)
    alpine_idx = c.biome_names.index("alpine")
    assert weights[alpine_idx] >= 0.9, \
        f"alpine weight at elev=40 should dominate; got {weights[alpine_idx]}"


def test_crossover_band_blends_both_biomes() -> None:
    """At elevation 10m (the catalog's intended crossover midpoint),
    BOTH biomes should have non-trivial weight — neither dominates."""
    c = KernelComposer(_walking_demo_catalog())
    weights = c.biome_weights(x=0.0, z=0.0, elev_m=10.0, slope_deg=5.0)
    forest_idx = c.biome_names.index("forest")
    alpine_idx = c.biome_names.index("alpine")
    assert weights[forest_idx] > 0.1, \
        f"forest should have non-trivial weight in crossover; got {weights[forest_idx]}"
    assert weights[alpine_idx] > 0.1, \
        f"alpine should have non-trivial weight in crossover; got {weights[alpine_idx]}"


# --- height composition (chain dispatch) ---


def test_sample_height_returns_finite_scalar() -> None:
    """For any (x, z), the composer's blended height must be a finite
    float. Walking_demo's noise_stack at amp=50m → bounded ±~50m."""
    c = KernelComposer(_walking_demo_catalog())
    h = c.sample_height(x=0.0, z=0.0, seed=42)
    assert isinstance(h, float)
    assert np.isfinite(h)
    assert -100.0 < h < 100.0  # roughly within kernel amplitude


def test_chain_of_one_matches_bare_noise_stack() -> None:
    """A `kernel: {type: noise_stack, params: ...}` field is shorthand
    for a chain of length 1. The composer's height for a single-biome
    catalog with that shorthand must match the bare NoiseStackKernel
    sampled at the same (x, z, seed)."""
    catalog = {
        "world_name": "single_biome_noise_only",
        "biomes": [{
            "name": "x",
            "auto_biome_rules": {
                "elevation_m": [-1000, 1000], "slope_deg": [0, 90],
                "band_width_elevation_m": 1.0, "band_width_slope_deg": 1.0,
            },
            "kernel": {
                "type": "noise_stack",
                "params": {"octaves": 6, "frequency": 1.0 / 512.0,
                           "lacunarity": 2.0, "gain": 0.5,
                           "amplitude": 50.0},
            },
        }],
    }
    c = KernelComposer(catalog)
    bare = NoiseStackKernel(octaves=6, frequency=1.0 / 512.0,
                            lacunarity=2.0, gain=0.5, amplitude=50.0)
    # Composer's sample_height should equal bare kernel's sample at (x,z)
    for (x, z) in [(0.0, 0.0), (100.0, -50.0), (-273.5, 314.2)]:
        h_composer = c.sample_height(x=x, z=z, seed=42)
        # Bare kernel sample_page produces a grid; we want a single
        # sample. Use a 1x1 grid centered at (x, z).
        bare_arr = bare.sample_page((x, z), extent_m=1.0, grid_n=2, seed=42)
        h_bare = float(bare_arr[0, 0])
        assert abs(h_composer - h_bare) < 1e-3, \
            f"composer height {h_composer} != bare kernel {h_bare} at ({x}, {z})"


def test_explicit_chain_dispatch_runs_stages_in_order() -> None:
    """An explicit `kernel: {type: chain, stages: [{type: noise_stack,
    params: ...}]}` should behave identically to the noise_stack
    shorthand. Verifies chain dispatch is back-compatible."""
    params = {"octaves": 4, "frequency": 1.0 / 256.0,
              "lacunarity": 2.0, "gain": 0.5, "amplitude": 30.0}
    shorthand = {
        "world_name": "shorthand",
        "biomes": [{
            "name": "x",
            "auto_biome_rules": {
                "elevation_m": [-1000, 1000], "slope_deg": [0, 90],
                "band_width_elevation_m": 1.0, "band_width_slope_deg": 1.0,
            },
            "kernel": {"type": "noise_stack", "params": params},
        }],
    }
    chain = {
        "world_name": "chain",
        "biomes": [{
            "name": "x",
            "auto_biome_rules": {
                "elevation_m": [-1000, 1000], "slope_deg": [0, 90],
                "band_width_elevation_m": 1.0, "band_width_slope_deg": 1.0,
            },
            "kernel": {"type": "chain", "stages": [
                {"type": "noise_stack", "params": params}
            ]},
        }],
    }
    c1 = KernelComposer(shorthand)
    c2 = KernelComposer(chain)
    for (x, z) in [(0.0, 0.0), (123.4, -567.8)]:
        h1 = c1.sample_height(x=x, z=z, seed=7)
        h2 = c2.sample_height(x=x, z=z, seed=7)
        assert abs(h1 - h2) < 1e-5, \
            f"shorthand {h1} != explicit chain {h2}"


# --- determinism (spec 19 Quality bar) ---


def test_deterministic_for_same_inputs() -> None:
    c = KernelComposer(_walking_demo_catalog())
    h_a = c.sample_height(x=100.0, z=200.0, seed=42)
    h_b = c.sample_height(x=100.0, z=200.0, seed=42)
    assert h_a == h_b


def test_different_seed_changes_height() -> None:
    c = KernelComposer(_walking_demo_catalog())
    h_a = c.sample_height(x=100.0, z=200.0, seed=1)
    h_b = c.sample_height(x=100.0, z=200.0, seed=2)
    assert h_a != h_b
