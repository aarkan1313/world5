"""W5 SpatialIndex — uniform grid spatial primitive.

Per spec 08. Stores items as (id, point) pairs; supports query_radius,
query_rect, query_nearest. Python side; GDScript mirror at
engine/scripts/core/SpatialIndex.gd.

Cross-impl parity per spec 06: identical query results for identical
insert sequences.
"""

from __future__ import annotations

import math
from typing import Iterable

import numpy as np

from world5.log import log

SYSTEM_NAME = "spatial_index"


class SpatialIndex:
    """Uniform-grid 2D XZ spatial index.

    Items are arbitrary opaque integer IDs the caller provides. The
    index does NOT own the items' data — just their IDs and points.
    """

    def __init__(self, bounds: tuple[float, float, float, float], cell_size_m: float = 32.0):
        """Construct with `bounds = (x0, z0, x1, z1)` + cell size.

        cell_size_m should come from QualityTiers.get_current()'s
        spatial_index_<workload>_cell_size_m field (per SA-S1.7); 32m
        is the catch-all default per spec 08.
        """
        if cell_size_m <= 0:
            raise ValueError(f"cell_size_m must be > 0; got {cell_size_m}")
        x0, z0, x1, z1 = bounds
        if x1 <= x0 or z1 <= z0:
            raise ValueError(f"invalid bounds: {bounds} (x1 must be > x0; z1 must be > z0)")
        self._bounds = bounds
        self._cell_size = cell_size_m
        self._cells: dict[tuple[int, int], list[int]] = {}
        self._items: dict[int, tuple[float, float]] = {}  # id -> (x, z)

    # --- mutation ---

    def insert(self, item_id: int, point: tuple[float, float]) -> None:
        """Insert an item at point. Overwrites if id already present."""
        if item_id in self._items:
            self.remove(item_id)
        self._items[item_id] = point
        cell = self._cell_for(point)
        self._cells.setdefault(cell, []).append(item_id)

    def remove(self, item_id: int) -> bool:
        """Remove item by id. Returns True if it existed."""
        if item_id not in self._items:
            return False
        point = self._items.pop(item_id)
        cell = self._cell_for(point)
        bucket = self._cells.get(cell)
        if bucket is not None:
            try:
                bucket.remove(item_id)
            except ValueError:
                pass
            if not bucket:
                del self._cells[cell]
        return True

    def update(self, item_id: int, new_point: tuple[float, float]) -> None:
        """Move an item to a new point. No-op if id unknown."""
        if item_id not in self._items:
            log.warn(SYSTEM_NAME, "update: unknown item", id=item_id)
            return
        self.remove(item_id)
        self.insert(item_id, new_point)

    def clear(self) -> None:
        self._cells.clear()
        self._items.clear()

    # --- queries ---

    def query_radius(self, center: tuple[float, float], radius_m: float) -> np.ndarray:
        """Return ids within `radius_m` of `center`. Order: deterministic
        per-cell scan order; tie-break by insertion order within a cell."""
        if radius_m < 0:
            return np.array([], dtype=np.int64)
        cx, cz = center
        r2 = radius_m * radius_m
        result: list[int] = []
        for cell in self._cells_overlapping_radius(center, radius_m):
            for item_id in self._cells[cell]:
                px, pz = self._items[item_id]
                dx = px - cx
                dz = pz - cz
                if dx * dx + dz * dz <= r2:
                    result.append(item_id)
        return np.array(result, dtype=np.int64)

    def query_rect(self, rect: tuple[float, float, float, float]) -> np.ndarray:
        """Return ids whose point is inside the axis-aligned rect."""
        x0, z0, x1, z1 = rect
        result: list[int] = []
        for cell in self._cells_overlapping_rect(rect):
            for item_id in self._cells[cell]:
                px, pz = self._items[item_id]
                if x0 <= px <= x1 and z0 <= pz <= z1:
                    result.append(item_id)
        return np.array(result, dtype=np.int64)

    def query_nearest(self, point: tuple[float, float], k: int = 1) -> np.ndarray:
        """Return up to k nearest ids to `point`. Order: nearest first.

        Strategy: expanding-ring cell search until we have k candidates
        in inspected cells, then exact distance sort.
        """
        if k <= 0 or not self._items:
            return np.array([], dtype=np.int64)
        cx, cz = point
        center_cell = self._cell_for(point)
        ring = 0
        candidates: list[int] = []
        # Expand rings until we have k candidates; then add one more ring
        # to ensure correctness (an item in a farther cell may be closer
        # than items in the inner ring near the cell border).
        max_ring = self._max_cell_dim()
        while len(candidates) < k and ring <= max_ring:
            for cell in self._ring_cells(center_cell, ring):
                if cell in self._cells:
                    candidates.extend(self._cells[cell])
            ring += 1
        # One additional safety ring to catch edge cases
        if ring <= max_ring:
            for cell in self._ring_cells(center_cell, ring):
                if cell in self._cells:
                    candidates.extend(self._cells[cell])
        if not candidates:
            return np.array([], dtype=np.int64)
        # Sort by distance, tiebreak by insertion order (stable)
        with_dist = []
        for item_id in candidates:
            px, pz = self._items[item_id]
            d2 = (px - cx) ** 2 + (pz - cz) ** 2
            with_dist.append((d2, item_id))
        with_dist.sort(key=lambda t: t[0])
        return np.array([t[1] for t in with_dist[:k]], dtype=np.int64)

    def contains(self, item_id: int) -> bool:
        return item_id in self._items

    # --- diagnostics ---

    def size(self) -> int:
        return len(self._items)

    def bucket_count(self) -> int:
        return len(self._cells)

    def max_bucket_load(self) -> int:
        if not self._cells:
            return 0
        return max(len(b) for b in self._cells.values())

    # --- internals ---

    def _cell_for(self, point: tuple[float, float]) -> tuple[int, int]:
        x, z = point
        return (int(math.floor(x / self._cell_size)), int(math.floor(z / self._cell_size)))

    def _cells_overlapping_radius(self, center: tuple[float, float], radius_m: float
                                  ) -> Iterable[tuple[int, int]]:
        cx, cz = center
        cs = self._cell_size
        x_min = int(math.floor((cx - radius_m) / cs))
        x_max = int(math.floor((cx + radius_m) / cs))
        z_min = int(math.floor((cz - radius_m) / cs))
        z_max = int(math.floor((cz + radius_m) / cs))
        for ix in range(x_min, x_max + 1):
            for iz in range(z_min, z_max + 1):
                if (ix, iz) in self._cells:
                    yield (ix, iz)

    def _cells_overlapping_rect(self, rect: tuple[float, float, float, float]
                                ) -> Iterable[tuple[int, int]]:
        x0, z0, x1, z1 = rect
        cs = self._cell_size
        x_min = int(math.floor(x0 / cs))
        x_max = int(math.floor(x1 / cs))
        z_min = int(math.floor(z0 / cs))
        z_max = int(math.floor(z1 / cs))
        for ix in range(x_min, x_max + 1):
            for iz in range(z_min, z_max + 1):
                if (ix, iz) in self._cells:
                    yield (ix, iz)

    def _ring_cells(self, center_cell: tuple[int, int], ring: int
                    ) -> Iterable[tuple[int, int]]:
        """Generate the cells at exactly `ring` distance (Chebyshev) from
        center_cell. ring=0 → just the center; ring=1 → 8 neighbors; etc."""
        cx, cz = center_cell
        if ring == 0:
            yield (cx, cz)
            return
        # Top + bottom rows
        for ix in range(cx - ring, cx + ring + 1):
            yield (ix, cz - ring)
            yield (ix, cz + ring)
        # Left + right cols (excluding corners already yielded)
        for iz in range(cz - ring + 1, cz + ring):
            yield (cx - ring, iz)
            yield (cx + ring, iz)

    def _max_cell_dim(self) -> int:
        """Max ring count needed to cover the index bounds."""
        x0, z0, x1, z1 = self._bounds
        cs = self._cell_size
        return max(int(math.ceil((x1 - x0) / cs)), int(math.ceil((z1 - z0) / cs)))
