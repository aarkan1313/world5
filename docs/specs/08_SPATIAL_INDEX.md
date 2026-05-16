# Spec: Spatial Index

> Status: draft
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT
> Consumed by: terrain page cache, decoration runtime LOD pass, nav region queries, future audio occlusion, future AI knowledge, future deformation-impact queries

## Purpose

A generic spatial-index primitive (grid / quadtree / spatial-hash) for
fast "what's near this point" queries.

W4.1's missing-layer #1 (per the audit). Every consumer iterated every
item it owned:
- Decoration LOD pass walked all 4500+ instances per tick
- Terrain page cache used dictionary-by-cache-key (no spatial query —
  manual bounding-box math each time)
- Material variant selection was hash-based per fragment (fine) but
  no nearest-neighbor lookup (fine while N small)
- Survey footprint computation was manual

The pattern was: "we have only N items, O(N) iteration is fine." Then
several systems hit the wall simultaneously when production scale
arrived. W5 builds the primitive once so every consumer uses the same
contract and never re-walks-everything.

Two implementations ship: Python (for pipeline use) and GDScript (for
runtime use). Same API shape; impl-level differences hidden.

## Non-goals

- Dynamic re-balancing for densely-clustered data (B-tree complexity
  isn't justified at our scale)
- Spanning multiple worlds (one index per world)
- 3D indexing as default (2D XZ is what terrain + decoration + nav
  need; 3D added later if/when caves require it)
- Concurrent writes (single-thread mutation; queries can be concurrent
  if backing data structure allows)

## Public API

### GDScript: `engine/scripts/core/SpatialIndex.gd`

```gdscript
class_name SpatialIndex extends RefCounted

# Configurable at construction:
# - bounds: AABB or Rect2 — world extents
# - cell_size_m: float — grid cell size, default 32m
# - backing: GRID | QUADTREE — first ships GRID; QUADTREE deferred

func _init(bounds: Rect2, cell_size_m: float = 32.0) -> void
# Per SA-S1.7: consumers SHOULD pick cell_size_m from
# QualityTiers.get_current()["spatial_index_<workload>_cell_size_m"]
# rather than use the default. Decoration uses
# spatial_index_decoration_cell_size_m (8m at high); terrain uses
# spatial_index_terrain_cell_size_m (64m); foliage uses
# spatial_index_foliage_cell_size_m (16m). Default 32m is the
# fallback when no workload-specific knob applies.

# Mutation
func insert(id: int, point: Vector2) -> void
func remove(id: int) -> bool   # true if existed
func update(id: int, new_point: Vector2) -> void  # remove + insert
func clear() -> void

# Queries
func query_radius(center: Vector2, radius_m: float) -> PackedInt32Array
func query_rect(rect: Rect2) -> PackedInt32Array
func query_nearest(point: Vector2, k: int = 1) -> PackedInt32Array
func contains(id: int) -> bool

# Diagnostics
func size() -> int                     # total items indexed
func bucket_count() -> int             # for tuning cell_size_m
func max_bucket_load() -> int          # for tuning cell_size_m
```

### Python: `pipeline/core/spatial_index.py`

```python
class SpatialIndex:
    def __init__(self, bounds: tuple[float, float, float, float], cell_size_m: float = 32.0): ...

    def insert(self, item_id: int, point: tuple[float, float]) -> None: ...
    def remove(self, item_id: int) -> bool: ...
    def update(self, item_id: int, new_point: tuple[float, float]) -> None: ...
    def clear(self) -> None: ...

    def query_radius(self, center: tuple[float, float], radius_m: float) -> np.ndarray: ...
    def query_rect(self, rect: tuple[float, float, float, float]) -> np.ndarray: ...
    def query_nearest(self, point: tuple[float, float], k: int = 1) -> np.ndarray: ...
    def contains(self, item_id: int) -> bool: ...

    def size(self) -> int: ...
    def bucket_count(self) -> int: ...
    def max_bucket_load(self) -> int: ...
```

Both APIs return arrays of opaque item IDs. Consumer maps IDs back to
its own data (decoration instance index, terrain chunk key, etc).

## Backing implementations

### V1: Uniform grid (ships first)
- Simplest possible. World divided into `cell_size_m` × `cell_size_m`
  cells. Each cell holds a list of item IDs.
- Insert/remove: O(1)
- query_radius: O(cells_in_radius × avg_items_per_cell)
- Works well when items are reasonably uniformly distributed (which
  decoration is, by design)
- Pathological case: huge cluster in one cell. Mitigated by
  `cell_size_m` tuning (consumer responsibility)

### V2: Loose quadtree (deferred)
- Build only if grid pathology hits a real consumer
- Adaptive subdivision when bucket load exceeds threshold
- Adds memory + complexity; ship only when V1's failure mode is real

## Producer / consumer contract

- **Produces**: spatial query results as `PackedInt32Array` of item IDs.
- **Consumes**: items as `(id, point)` pairs from any producer. The
  index does NOT own the items' data — just their IDs and positions.

## Cross-impl parity

The Python and GDScript impls share a test suite that ensures identical
query results for identical insert sequences. (Pattern from W4.1's
kernel cross-impl test.) Lives at `tests/test_spatial_index_cross_impl.py`.

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `numpy` (Python side, for PackedInt32Array equivalent)

## Quality bar

- Insert 10k items + query_radius(r=100m) returns in < 1ms (Python)
- Insert 10k items + query_radius(r=100m) returns in < 5ms (GDScript)
- Update (move-by-1m for all items) returns in < 10ms for 10k items
- Cross-impl parity: 0 differences in query results for any test
  sequence
- Memory: ~80 bytes per indexed item (Python); ~60 bytes (GDScript)
- 100% test coverage of public API

## Discoverability

- **Entry point**: `SpatialIndex` class (Python or GDScript). Construct
  with bounds + cell size.
- **Schema**: GDScript class signature + Python type hints are the
  schema; both APIs documented in this spec
- **Validator / preflight**: cross-impl test catches API drift; gut/pytest
  suites cover behavior
- **Example**: `engine/examples/spatial_index_example.tscn` for GDScript;
  `pipeline/core/examples/spatial_index_example.py` for Python
- **Deterministic outputs**: yes for query_radius/rect; query_nearest
  tie-breaks by insertion order (stable)

## Open questions

- Should query results be sorted by distance (for `query_radius`)?
  Currently no — caller sorts if needed. Add a `sorted=True` kwarg
  if a real consumer wants it.
- Should `update()` be optimized vs naive remove+insert? Probably yes
  if items move a lot (decoration moves rarely; terrain pages never).
  Defer until measured.
- Quadtree backing: build now or wait for real pathology? Wait.

## References

- W4.1 retrospective + audit: missing-layer #1 ("Spatial-index
  primitive") — this spec is the direct response
- Audit cost estimate: 1-2 sessions; this matches the spec complexity

## Revision history

- 2026-05-16: initial draft
