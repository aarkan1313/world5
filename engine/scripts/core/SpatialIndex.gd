## W5 SpatialIndex — uniform-grid 2D XZ spatial primitive.
##
## Per spec 08. Mirror of pipeline/world5/spatial_index.py. Items are
## arbitrary opaque int IDs the caller provides.
##
## Constructed per-workload with cell_size_m from
## QualityTiers.get_current() (decoration=8m, terrain=64m, foliage=16m,
## default=32m per SA-S1.7).
##
## Cross-impl parity per spec 06 + tests/integration/test_spatial_index_cross_impl.py.

class_name SpatialIndex extends RefCounted

const SYSTEM_NAME: String = "spatial_index"

# Configurable at construction
var _bounds: Rect2  # using Rect2 for (x0, z0, w, h); convert via Rect2(x0, z0, x1-x0, z1-z0)
var _cell_size: float = 32.0

# cell_key (PackedInt32Array [ix, iz]) → Array of item_ids
var _cells: Dictionary = {}
# item_id → Vector2 point
var _items: Dictionary = {}


func _init(bounds: Rect2, cell_size_m: float = 32.0) -> void:
	assert(cell_size_m > 0.0, "cell_size_m must be > 0")
	assert(bounds.size.x > 0 and bounds.size.y > 0, "bounds size must be > 0")
	_bounds = bounds
	_cell_size = cell_size_m


# --- mutation ---

## Insert item at point. Overwrites if id already present.
func insert(item_id: int, point: Vector2) -> void:
	if _items.has(item_id):
		remove(item_id)
	_items[item_id] = point
	var cell := _cell_for(point)
	if not _cells.has(cell):
		_cells[cell] = [] as Array[int]
	(_cells[cell] as Array).append(item_id)


## Remove item by id. Returns true if it existed.
func remove(item_id: int) -> bool:
	if not _items.has(item_id):
		return false
	var point: Vector2 = _items[item_id]
	_items.erase(item_id)
	var cell := _cell_for(point)
	if _cells.has(cell):
		var bucket: Array = _cells[cell]
		bucket.erase(item_id)
		if bucket.is_empty():
			_cells.erase(cell)
	return true


## Move an item. No-op if id unknown (logs warning).
func update(item_id: int, new_point: Vector2) -> void:
	if not _items.has(item_id):
		Log.warn(SYSTEM_NAME, "update: unknown item", {"id": item_id})
		return
	remove(item_id)
	insert(item_id, new_point)


func clear() -> void:
	_cells.clear()
	_items.clear()


# --- queries ---

## Return ids within radius_m of center.
func query_radius(center: Vector2, radius_m: float) -> PackedInt32Array:
	var result: PackedInt32Array = []
	if radius_m < 0.0:
		return result
	var r2 := radius_m * radius_m
	for cell in _cells_overlapping_radius(center, radius_m):
		for item_id in _cells[cell]:
			var p: Vector2 = _items[item_id]
			var dx := p.x - center.x
			var dz := p.y - center.y
			if dx * dx + dz * dz <= r2:
				result.append(item_id)
	return result


## Return ids whose point is inside the rect.
func query_rect(rect: Rect2) -> PackedInt32Array:
	var result: PackedInt32Array = []
	for cell in _cells_overlapping_rect(rect):
		for item_id in _cells[cell]:
			var p: Vector2 = _items[item_id]
			if rect.has_point(p):
				result.append(item_id)
	return result


## Return up to k nearest ids to point. Nearest first; insertion-order
## tiebreak on ties.
func query_nearest(point: Vector2, k: int = 1) -> PackedInt32Array:
	if k <= 0 or _items.is_empty():
		return [] as PackedInt32Array
	var center_cell := _cell_for(point)
	var ring := 0
	var candidates: Array[int] = []
	var max_ring := _max_cell_dim()
	while candidates.size() < k and ring <= max_ring:
		for cell in _ring_cells(center_cell, ring):
			if _cells.has(cell):
				for id in _cells[cell]:
					candidates.append(id)
		ring += 1
	# One additional safety ring for edge cases
	if ring <= max_ring:
		for cell in _ring_cells(center_cell, ring):
			if _cells.has(cell):
				for id in _cells[cell]:
					candidates.append(id)
	if candidates.is_empty():
		return [] as PackedInt32Array
	# Sort by distance, tiebreak by insertion order
	var with_dist: Array = []
	for item_id in candidates:
		var p: Vector2 = _items[item_id]
		var d2: float = (p.x - point.x) ** 2 + (p.y - point.y) ** 2
		with_dist.append([d2, item_id])
	with_dist.sort_custom(func(a, b): return a[0] < b[0])
	var result: PackedInt32Array = []
	for i in range(min(k, with_dist.size())):
		result.append(with_dist[i][1])
	return result


func contains(item_id: int) -> bool:
	return _items.has(item_id)


# --- diagnostics ---

func size() -> int:
	return _items.size()


func bucket_count() -> int:
	return _cells.size()


func max_bucket_load() -> int:
	var max_load := 0
	for k in _cells.keys():
		var s: int = (_cells[k] as Array).size()
		if s > max_load:
			max_load = s
	return max_load


# --- internals ---

func _cell_for(point: Vector2) -> PackedInt32Array:
	return [int(floor(point.x / _cell_size)), int(floor(point.y / _cell_size))]


func _cells_overlapping_radius(center: Vector2, radius_m: float) -> Array:
	var cs := _cell_size
	var x_min := int(floor((center.x - radius_m) / cs))
	var x_max := int(floor((center.x + radius_m) / cs))
	var z_min := int(floor((center.y - radius_m) / cs))
	var z_max := int(floor((center.y + radius_m) / cs))
	var out: Array = []
	for ix in range(x_min, x_max + 1):
		for iz in range(z_min, z_max + 1):
			var cell: PackedInt32Array = [ix, iz]
			if _cells.has(cell):
				out.append(cell)
	return out


func _cells_overlapping_rect(rect: Rect2) -> Array:
	var cs := _cell_size
	var x_min := int(floor(rect.position.x / cs))
	var x_max := int(floor((rect.position.x + rect.size.x) / cs))
	var z_min := int(floor(rect.position.y / cs))
	var z_max := int(floor((rect.position.y + rect.size.y) / cs))
	var out: Array = []
	for ix in range(x_min, x_max + 1):
		for iz in range(z_min, z_max + 1):
			var cell: PackedInt32Array = [ix, iz]
			if _cells.has(cell):
				out.append(cell)
	return out


func _ring_cells(center_cell: PackedInt32Array, ring: int) -> Array:
	var cx: int = center_cell[0]
	var cz: int = center_cell[1]
	var out: Array = []
	if ring == 0:
		out.append([cx, cz] as PackedInt32Array)
		return out
	# Top + bottom rows
	for ix in range(cx - ring, cx + ring + 1):
		out.append([ix, cz - ring] as PackedInt32Array)
		out.append([ix, cz + ring] as PackedInt32Array)
	# Left + right cols (excluding corners)
	for iz in range(cz - ring + 1, cz + ring):
		out.append([cx - ring, iz] as PackedInt32Array)
		out.append([cx + ring, iz] as PackedInt32Array)
	return out


func _max_cell_dim() -> int:
	var cs := _cell_size
	return max(int(ceil(_bounds.size.x / cs)), int(ceil(_bounds.size.y / cs)))
