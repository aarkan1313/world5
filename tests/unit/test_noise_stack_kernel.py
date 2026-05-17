"""Unit tests for the NoiseStackKernel Python reference.

Doesn't require Godot. Verifies the kernel is deterministic, returns
expected shape/dtype, and produces finite values within amplitude
bound. Cross-impl parity vs GPU lives in tests/integration/.
"""

from __future__ import annotations

import numpy as np
import pytest

from world5.kernels import NoiseStackKernel


def test_sample_page_shape_and_dtype() -> None:
    k = NoiseStackKernel()
    arr = k.sample_page((0.0, 0.0), 256.0, 32, seed=0)
    assert arr.shape == (32, 32)
    assert arr.dtype == np.float32


def test_deterministic_for_same_seed() -> None:
    k = NoiseStackKernel()
    a = k.sample_page((100.0, 200.0), 256.0, 16, seed=42)
    b = k.sample_page((100.0, 200.0), 256.0, 16, seed=42)
    np.testing.assert_array_equal(a, b)


def test_seed_changes_output() -> None:
    k = NoiseStackKernel()
    a = k.sample_page((0.0, 0.0), 256.0, 16, seed=1)
    b = k.sample_page((0.0, 0.0), 256.0, 16, seed=2)
    # At least 50% of samples differ
    diffs = np.abs(a - b) > 1e-3
    assert diffs.sum() > (a.size // 2)


def test_position_changes_output() -> None:
    k = NoiseStackKernel()
    a = k.sample_page((0.0, 0.0), 256.0, 16, seed=0)
    b = k.sample_page((1000.0, 0.0), 256.0, 16, seed=0)
    # Same seed, different origin -> different output (different fbm samples)
    diffs = np.abs(a - b) > 1e-3
    assert diffs.sum() > (a.size // 2)


def test_finite_values_within_amplitude() -> None:
    k = NoiseStackKernel(amplitude=50.0)
    arr = k.sample_page((0.0, 0.0), 256.0, 64, seed=7)
    assert np.all(np.isfinite(arr))
    # fBm normalized to roughly [-1, 1] then scaled by amplitude
    assert np.all(np.abs(arr) < 75.0)  # generous bound (norm only approx)


def test_grid_n_equals_one_is_valid_edge_case() -> None:
    k = NoiseStackKernel()
    arr = k.sample_page((0.0, 0.0), 256.0, 1, seed=0)
    assert arr.shape == (1, 1)
    assert np.isfinite(arr[0, 0])


def test_corners_match_neighbors() -> None:
    """Adjacent samples in a small page should be smoothly varying
    (no extreme discontinuities — value noise is C1)."""
    k = NoiseStackKernel(amplitude=50.0)
    arr = k.sample_page((0.0, 0.0), 256.0, 8, seed=0)
    # Horizontal first differences should all be moderate
    h_diffs = np.abs(np.diff(arr, axis=1))
    assert h_diffs.max() < 50.0, (
        "neighboring samples should not differ by >50m for an 8x8 / 256m page"
    )
