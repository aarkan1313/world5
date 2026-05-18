"""Unit tests for the DemFeatureKernel Python reference (Sprint 2).

Spec 19 DemFeatureKernel — extracts ridge / drainage / slope / aspect
features from a real DEM so the composer can blend DEM-derived
features into a noise+erosion chain (geology-anchored worlds).

These tests use synthetic DEM arrays (controlled shapes — pyramids,
ramps, sinks) so we can verify each feature mode produces the expected
qualitative output. Loader/IO is tested separately with on-disk fixtures.
"""

from __future__ import annotations

import numpy as np
import pytest

from world5.kernels import DemFeatureKernel, DemFeatureResult


# --- construction + contract ---


def test_constructible_with_defaults() -> None:
    k = DemFeatureKernel()
    assert k.dem_path == ""
    assert "ridge_emphasis" in k.modes
    assert k.ridge_smooth_sigma_cells > 0.0


def test_extract_returns_dict_keyed_by_mode() -> None:
    h = np.zeros((16, 16), dtype=np.float32)
    k = DemFeatureKernel(modes=("ridge_emphasis", "slope_deg"))
    out = k.extract((0.0, 0.0), (16.0, 16.0), 16, dem_array=h)
    assert isinstance(out, DemFeatureResult)
    assert set(out.features.keys()) == {"ridge_emphasis", "slope_deg"}


def test_extract_output_shape_matches_grid_n() -> None:
    h = np.zeros((32, 32), dtype=np.float32)
    k = DemFeatureKernel(modes=("slope_deg",))
    out = k.extract((0.0, 0.0), (32.0, 32.0), 24, dem_array=h)
    assert out.features["slope_deg"].shape == (24, 24)
    assert out.features["slope_deg"].dtype == np.float32


def test_extract_rejects_zero_grid_n() -> None:
    h = np.zeros((8, 8), dtype=np.float32)
    k = DemFeatureKernel(modes=("slope_deg",))
    with pytest.raises(ValueError):
        k.extract((0.0, 0.0), (8.0, 8.0), 0, dem_array=h)


def test_extract_rejects_unknown_mode() -> None:
    h = np.zeros((8, 8), dtype=np.float32)
    k = DemFeatureKernel(modes=("not_a_real_mode",))
    with pytest.raises(ValueError):
        k.extract((0.0, 0.0), (8.0, 8.0), 8, dem_array=h)


def test_extract_rejects_non_2d_array() -> None:
    h = np.zeros((4, 4, 3), dtype=np.float32)
    k = DemFeatureKernel(modes=("slope_deg",))
    with pytest.raises(ValueError):
        k.extract((0.0, 0.0), (4.0, 4.0), 4, dem_array=h)


# --- ridge_emphasis: detects raised features ---


def _pyramid(n: int, peak: float = 10.0) -> np.ndarray:
    """n×n pyramid centered on grid. Peak at center; linear falloff."""
    cy = (n - 1) / 2.0
    cx = (n - 1) / 2.0
    y, x = np.ogrid[:n, :n]
    dist = np.maximum(np.abs(y - cy), np.abs(x - cx))
    h = peak * (1.0 - dist / max(cy, cx))
    return np.clip(h, 0.0, peak).astype(np.float32)


def test_ridge_emphasis_peaks_at_pyramid_top() -> None:
    h = _pyramid(32, peak=50.0)
    k = DemFeatureKernel(modes=("ridge_emphasis",), ridge_smooth_sigma_cells=1.0)
    out = k.extract((0.0, 0.0), (32.0, 32.0), 32, dem_array=h)
    r = out.features["ridge_emphasis"]
    # Peak of ridge_emphasis should be near pyramid summit (center).
    peak_idx = np.unravel_index(np.argmax(r), r.shape)
    cy, cx = (r.shape[0] - 1) / 2.0, (r.shape[1] - 1) / 2.0
    dist_from_center = np.hypot(peak_idx[0] - cy, peak_idx[1] - cx)
    assert dist_from_center < 4.0, (
        f"ridge peak at {peak_idx} should be within 4 cells of center "
        f"({cy:.1f}, {cx:.1f})"
    )


def test_ridge_emphasis_normalized_to_unit_range() -> None:
    h = _pyramid(16, peak=20.0)
    k = DemFeatureKernel(modes=("ridge_emphasis",))
    out = k.extract((0.0, 0.0), (16.0, 16.0), 16, dem_array=h)
    r = out.features["ridge_emphasis"]
    assert r.min() >= 0.0 - 1e-6
    assert r.max() <= 1.0 + 1e-6
    # Some signal should exist on a pyramid.
    assert r.max() > 0.1


def test_ridge_emphasis_zero_on_flat_terrain() -> None:
    h = np.full((16, 16), 100.0, dtype=np.float32)
    k = DemFeatureKernel(modes=("ridge_emphasis",))
    out = k.extract((0.0, 0.0), (16.0, 16.0), 16, dem_array=h)
    r = out.features["ridge_emphasis"]
    # Flat terrain has zero curvature; normalized output is all zeros.
    assert float(np.max(np.abs(r))) < 1e-5


# --- drainage_accumulation: water flow ---


def test_drainage_accumulation_unit_range() -> None:
    # A simple ramp from high (top) to low (bottom): water all flows
    # to the bottom edge, accumulation should be highest there.
    n = 16
    h = np.zeros((n, n), dtype=np.float32)
    for r in range(n):
        h[r, :] = float(n - 1 - r)  # row 0 highest, row n-1 lowest
    k = DemFeatureKernel(modes=("drainage_accumulation",))
    out = k.extract((0.0, 0.0), (float(n), float(n)), n, dem_array=h)
    d = out.features["drainage_accumulation"]
    assert d.shape == (n, n)
    assert d.min() >= 0.0 - 1e-6
    assert d.max() <= 1.0 + 1e-6


def test_drainage_accumulation_bottom_row_high() -> None:
    # Same ramp; bottom row should accumulate the most flow.
    n = 16
    h = np.zeros((n, n), dtype=np.float32)
    for r in range(n):
        h[r, :] = float(n - 1 - r)
    k = DemFeatureKernel(modes=("drainage_accumulation",))
    out = k.extract((0.0, 0.0), (float(n), float(n)), n, dem_array=h)
    d = out.features["drainage_accumulation"]
    # Bottom row mean should exceed top row mean significantly.
    assert d[-1, :].mean() > d[0, :].mean() + 0.1


# --- slope_deg + aspect_deg ---


def test_slope_deg_zero_on_flat() -> None:
    h = np.full((16, 16), 5.0, dtype=np.float32)
    k = DemFeatureKernel(modes=("slope_deg",))
    out = k.extract((0.0, 0.0), (16.0, 16.0), 16, dem_array=h)
    s = out.features["slope_deg"]
    assert float(np.max(np.abs(s))) < 1e-3


def test_slope_deg_in_expected_range() -> None:
    h = _pyramid(32, peak=50.0)
    k = DemFeatureKernel(modes=("slope_deg",))
    out = k.extract((0.0, 0.0), (32.0, 32.0), 32, dem_array=h)
    s = out.features["slope_deg"]
    assert s.min() >= 0.0
    assert s.max() <= 90.0
    # Pyramid sides have nonzero slope somewhere.
    assert s.max() > 5.0


def test_aspect_deg_in_compass_range() -> None:
    h = _pyramid(16, peak=10.0)
    k = DemFeatureKernel(modes=("aspect_deg",))
    out = k.extract((0.0, 0.0), (16.0, 16.0), 16, dem_array=h)
    a = out.features["aspect_deg"]
    assert a.min() >= 0.0
    assert a.max() < 360.0 + 1e-3


# --- multi-mode extraction ---


def test_multi_mode_extract_runs_all() -> None:
    h = _pyramid(20, peak=15.0)
    k = DemFeatureKernel(modes=(
        "ridge_emphasis", "drainage_accumulation", "slope_deg", "aspect_deg",
    ))
    out = k.extract((0.0, 0.0), (20.0, 20.0), 20, dem_array=h)
    assert set(out.features.keys()) == {
        "ridge_emphasis", "drainage_accumulation", "slope_deg", "aspect_deg",
    }
    for arr in out.features.values():
        assert arr.shape == (20, 20)
        assert arr.dtype == np.float32


# --- determinism ---


def test_same_input_gives_byte_identical_output() -> None:
    h = _pyramid(24, peak=10.0)
    k = DemFeatureKernel(modes=("ridge_emphasis", "drainage_accumulation"))
    out_a = k.extract((0.0, 0.0), (24.0, 24.0), 24, dem_array=h)
    out_b = k.extract((0.0, 0.0), (24.0, 24.0), 24, dem_array=h)
    for mode in out_a.features:
        np.testing.assert_array_equal(out_a.features[mode], out_b.features[mode])


# --- loader ---


def test_load_dem_missing_path_raises() -> None:
    k = DemFeatureKernel(dem_path="")
    with pytest.raises(ValueError):
        k.extract((0.0, 0.0), (16.0, 16.0), 16)


def test_load_dem_nonexistent_path_raises() -> None:
    k = DemFeatureKernel(dem_path="not_a_real_path.tif")
    with pytest.raises(FileNotFoundError):
        k.extract((0.0, 0.0), (16.0, 16.0), 16)


def test_load_dem_npy_round_trip(tmp_path) -> None:
    p = tmp_path / "test_dem.npy"
    h = _pyramid(16, peak=8.0)
    np.save(p, h)
    k = DemFeatureKernel(dem_path=str(p), modes=("slope_deg",))
    out = k.extract((0.0, 0.0), (16.0, 16.0), 16)
    assert out.features["slope_deg"].shape == (16, 16)
