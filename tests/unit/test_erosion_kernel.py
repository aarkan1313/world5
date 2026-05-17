"""Unit tests for the ErosionKernel Python reference (Phase 5.7.a).

Spec 19 ErosionKernel — hydraulic + thermal erosion over a pre-
existing heightmap. Outputs: eroded height field + drainage_map +
flow_direction + flow_accumulation per spec 19 §"Auxiliary outputs".

Per superpowers:test-driven-development: one test at a time, write
the test first, verify RED, then implement minimum to GREEN.

Algorithm references:
- Hydraulic: Mei et al. 2007 'Fast Hydraulic Erosion Simulation
  and Visualization on GPU' (Pacific Graphics)
- Thermal: Musgrave/Kolb angle-of-repose-driven slope diffusion
"""

from __future__ import annotations

import numpy as np
import pytest

from world5.kernels import ErosionKernel


# --- contract: construct + erode shape/dtype ---


def test_constructible_with_defaults() -> None:
    k = ErosionKernel(iterations=10)
    assert k.iterations == 10
    assert k.rain_rate > 0.0
    assert 0.0 <= k.evaporation <= 1.0
    assert k.sediment_capacity > 0.0


def test_erode_returns_same_shape_and_dtype() -> None:
    h = np.zeros((32, 32), dtype=np.float32)
    k = ErosionKernel(iterations=1)
    out = k.erode(h)
    assert out.eroded.shape == (32, 32)
    assert out.eroded.dtype == np.float32
    assert out.drainage_map.shape == (32, 32)
    assert out.flow_direction.shape == (32, 32, 2)
    assert out.flow_accumulation.shape == (32, 32)


def test_erode_flat_input_returns_flat_output() -> None:
    """Flat input + no thermal pass + rain = should stay (near-)flat
    because there's no slope to drive sediment movement."""
    h = np.full((16, 16), 0.5, dtype=np.float32)
    k = ErosionKernel(iterations=20, thermal_iterations=0)
    out = k.erode(h)
    # Allow tiny numerical drift but no large erosion on flat input
    np.testing.assert_allclose(out.eroded, h, atol=1e-3)


# --- determinism (spec 19 Quality bar) ---


def test_deterministic_same_input_same_output() -> None:
    h = _single_peak(16, peak_height=2.0)
    k = ErosionKernel(iterations=10, seed=42)
    out_a = k.erode(h)
    out_b = k.erode(h)
    np.testing.assert_array_equal(out_a.eroded, out_b.eroded)
    np.testing.assert_array_equal(out_a.drainage_map, out_b.drainage_map)


# --- bounds (spec 19 §"World-size bound") ---


def test_erode_preserves_bounded_range() -> None:
    """Eroded heights stay within sane bounds — no NaN/Inf, no
    runaway growth. We don't require strict equality of bounds (the
    deposition can raise some cells slightly), but the range
    shouldn't drift more than 2x the original amplitude."""
    h = _single_peak(16, peak_height=2.0)
    k = ErosionKernel(iterations=30, thermal_iterations=10)
    out = k.erode(h)
    assert np.isfinite(out.eroded).all(), "no NaN/Inf in eroded heights"
    original_range = float(h.max() - h.min())
    eroded_range = float(out.eroded.max() - out.eroded.min())
    assert eroded_range <= original_range * 2.0, \
        f"eroded range {eroded_range} > 2x original {original_range}"


# --- drainage / flow auxiliary outputs (spec 35 + 41 consumers) ---


def test_drainage_radial_on_single_peak() -> None:
    """Spec 19 §Auxiliary outputs: drainage_map records accumulated
    water OUTFLOW per cell over the simulation. With rain falling
    uniformly + a central peak, cells far from the peak accumulate
    more outflow because water from upslope passes through them on
    its way to the boundary. The peak itself has lower outflow
    (only its own rain leaves; nothing flows IN from above).

    Sanity check: peak (center, no upslope) < outer ring (gets all
    the drained water from upslope sweeping outward)."""
    h = _single_peak(32, peak_height=5.0)
    k = ErosionKernel(iterations=30)
    out = k.erode(h)
    peak_cell = float(out.drainage_map[16, 16])
    ring_outer = _ring_avg(out.drainage_map, center=16, radius=12, width=2)
    assert ring_outer > peak_cell, \
        f"outer-ring drainage {ring_outer} should exceed peak {peak_cell} " \
        "(downslope cells accumulate upslope water)"


def test_flow_direction_points_downhill_on_slope() -> None:
    """Spec 35: flow_direction is per-cell flow vector. On a simple
    +x ramp, flow should be in the -x direction (toward lower z)."""
    n = 16
    h = np.tile(np.linspace(0.0, 5.0, n, dtype=np.float32), (n, 1))  # h[r,c] increases with c
    k = ErosionKernel(iterations=5)
    out = k.erode(h)
    # Interior cells (avoid edges): mean flow vector should point in -x
    interior = out.flow_direction[2:-2, 2:-2]
    mean_dx = float(interior[..., 0].mean())
    # Negative dx = flow toward lower-x = downhill direction here
    assert mean_dx < 0.0, \
        f"mean flow x should be negative on +x ramp (got {mean_dx})"


# --- thermal-only mode ---


def test_thermal_slumps_steep_slopes() -> None:
    """A single tall thin peak above the talus angle should be slumped
    shorter after thermal erosion."""
    h = _single_peak(16, peak_height=10.0)
    peak_before = float(h.max())
    k = ErosionKernel(iterations=0, thermal_iterations=50,
                      talus_angle_deg=30.0, talus_rate=0.5)
    out = k.erode(h)
    peak_after = float(out.eroded.max())
    assert peak_after < peak_before, \
        f"thermal pass should reduce peak height ({peak_after} vs {peak_before})"


# --- helpers ---


def _single_peak(n: int, peak_height: float) -> np.ndarray:
    """Build a (n, n) heightmap with a single centered Gaussian-ish
    peak. Used as a regression fixture for radial drainage tests."""
    cy, cx = (n - 1) / 2.0, (n - 1) / 2.0
    rr, cc = np.indices((n, n), dtype=np.float32)
    dist = np.sqrt((rr - cy) ** 2 + (cc - cx) ** 2)
    sigma = max(n / 6.0, 1.0)
    return (peak_height * np.exp(-(dist ** 2) / (2.0 * sigma ** 2))).astype(np.float32)


def _ring_avg(arr: np.ndarray, center: int, radius: int, width: int) -> float:
    """Average values in arr inside a thin ring around `center`."""
    rr, cc = np.indices(arr.shape, dtype=np.float32)
    dist = np.sqrt((rr - center) ** 2 + (cc - center) ** 2)
    mask = (dist >= radius - width / 2.0) & (dist <= radius + width / 2.0)
    return float(arr[mask].mean()) if mask.any() else 0.0
