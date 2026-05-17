"""Tests for world5.spatial_index.SpatialIndex (Python side).

Per spec 06 + spec 08.
"""

from __future__ import annotations

import pytest

from world5.spatial_index import SpatialIndex


@pytest.fixture
def empty_index() -> SpatialIndex:
    return SpatialIndex(bounds=(-100.0, -100.0, 100.0, 100.0), cell_size_m=10.0)


@pytest.fixture
def populated_index() -> SpatialIndex:
    idx = SpatialIndex(bounds=(-100.0, -100.0, 100.0, 100.0), cell_size_m=10.0)
    # 5 items at known positions
    idx.insert(1, (0.0, 0.0))
    idx.insert(2, (5.0, 5.0))
    idx.insert(3, (50.0, 50.0))
    idx.insert(4, (-30.0, 20.0))
    idx.insert(5, (0.1, 0.1))  # near id 1
    return idx


# --- construction ---

def test_invalid_cell_size_raises():
    with pytest.raises(ValueError):
        SpatialIndex(bounds=(-10.0, -10.0, 10.0, 10.0), cell_size_m=0)


def test_invalid_bounds_raises():
    with pytest.raises(ValueError):
        SpatialIndex(bounds=(10.0, 10.0, 0.0, 0.0))


# --- mutation ---

def test_empty_index_size_zero(empty_index):
    assert empty_index.size() == 0
    assert empty_index.bucket_count() == 0


def test_insert_increments_size(empty_index):
    empty_index.insert(42, (1.0, 1.0))
    assert empty_index.size() == 1
    assert empty_index.contains(42)


def test_remove_decrements_size(populated_index):
    assert populated_index.size() == 5
    assert populated_index.remove(3) is True
    assert populated_index.size() == 4
    assert not populated_index.contains(3)


def test_remove_unknown_returns_false(empty_index):
    assert empty_index.remove(99) is False


def test_update_moves_item(populated_index):
    populated_index.update(1, (90.0, 90.0))
    # Old location no longer has id 1
    near_origin = populated_index.query_radius((0.0, 0.0), 1.0)
    assert 1 not in near_origin.tolist()
    # New location does
    near_corner = populated_index.query_radius((90.0, 90.0), 1.0)
    assert 1 in near_corner.tolist()


def test_clear(populated_index):
    populated_index.clear()
    assert populated_index.size() == 0


# --- queries ---

def test_query_radius_finds_close_items(populated_index):
    ids = populated_index.query_radius((0.0, 0.0), 1.0)
    # ids 1 and 5 are within 1m of origin
    assert set(ids.tolist()) == {1, 5}


def test_query_radius_finds_all_within_large_radius(populated_index):
    ids = populated_index.query_radius((0.0, 0.0), 200.0)
    assert set(ids.tolist()) == {1, 2, 3, 4, 5}


def test_query_radius_negative_returns_empty(populated_index):
    ids = populated_index.query_radius((0.0, 0.0), -1.0)
    assert len(ids) == 0


def test_query_rect_finds_inside(populated_index):
    # Rect covering ids 1, 2, 5 (all near origin)
    ids = populated_index.query_rect((-1.0, -1.0, 10.0, 10.0))
    assert set(ids.tolist()) == {1, 2, 5}


def test_query_nearest_k1(populated_index):
    # Nearest to origin should be 1 or 5 (both at ~origin)
    ids = populated_index.query_nearest((0.0, 0.0), k=1)
    assert len(ids) == 1
    assert ids[0] in (1, 5)


def test_query_nearest_k3_nearest_first(populated_index):
    ids = populated_index.query_nearest((0.0, 0.0), k=3)
    # Expect 1, 5, 2 in some order with 1 or 5 first
    result = ids.tolist()
    assert len(result) == 3
    assert set(result[:2]) == {1, 5}
    assert result[2] == 2  # next closest at (5,5)


def test_query_nearest_returns_at_most_k(populated_index):
    ids = populated_index.query_nearest((0.0, 0.0), k=100)
    assert len(ids) == 5  # only 5 items in index


def test_query_nearest_k0_empty(populated_index):
    ids = populated_index.query_nearest((0.0, 0.0), k=0)
    assert len(ids) == 0


def test_query_nearest_empty_index(empty_index):
    ids = empty_index.query_nearest((0.0, 0.0), k=5)
    assert len(ids) == 0


# --- diagnostics ---

def test_bucket_count_increases_with_distinct_cells(empty_index):
    # All items at one location → 1 bucket
    empty_index.insert(1, (0.0, 0.0))
    empty_index.insert(2, (0.1, 0.1))
    assert empty_index.bucket_count() == 1
    # Far apart → 2 buckets
    empty_index.insert(3, (50.0, 50.0))
    assert empty_index.bucket_count() == 2


def test_max_bucket_load(empty_index):
    for i in range(5):
        empty_index.insert(i, (0.0, 0.0))  # all in one cell
    assert empty_index.max_bucket_load() == 5


# --- determinism ---

def test_query_radius_deterministic(populated_index):
    """Same inputs → same outputs (order matters for downstream consumers)."""
    r1 = populated_index.query_radius((0.0, 0.0), 50.0).tolist()
    r2 = populated_index.query_radius((0.0, 0.0), 50.0).tolist()
    assert r1 == r2
