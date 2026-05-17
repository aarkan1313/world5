## Tests for SpatialIndex.gd (GDScript side).
##
## Mirror of tests/unit/test_spatial_index.py for cross-impl parity.

extends GutTest


var _idx: SpatialIndex


func before_each() -> void:
	_idx = SpatialIndex.new(Rect2(-100, -100, 200, 200), 10.0)


func _populate() -> void:
	_idx.insert(1, Vector2(0.0, 0.0))
	_idx.insert(2, Vector2(5.0, 5.0))
	_idx.insert(3, Vector2(50.0, 50.0))
	_idx.insert(4, Vector2(-30.0, 20.0))
	_idx.insert(5, Vector2(0.1, 0.1))


# --- mutation ---

func test_empty_size_zero() -> void:
	assert_eq(_idx.size(), 0)
	assert_eq(_idx.bucket_count(), 0)


func test_insert_increments() -> void:
	_idx.insert(42, Vector2(1.0, 1.0))
	assert_eq(_idx.size(), 1)
	assert_true(_idx.contains(42))


func test_remove_decrements() -> void:
	_populate()
	assert_eq(_idx.size(), 5)
	assert_true(_idx.remove(3))
	assert_eq(_idx.size(), 4)
	assert_false(_idx.contains(3))


func test_remove_unknown_returns_false() -> void:
	assert_false(_idx.remove(99))


func test_update_moves_item() -> void:
	_populate()
	_idx.update(1, Vector2(90, 90))
	var near_origin := _idx.query_radius(Vector2(0, 0), 1.0)
	assert_false(near_origin.has(1))
	var near_corner := _idx.query_radius(Vector2(90, 90), 1.0)
	assert_true(near_corner.has(1))


func test_clear() -> void:
	_populate()
	_idx.clear()
	assert_eq(_idx.size(), 0)


# --- queries ---

func test_query_radius_finds_close_items() -> void:
	_populate()
	var ids := _idx.query_radius(Vector2(0, 0), 1.0)
	# ids 1 and 5 within 1m of origin
	assert_eq(ids.size(), 2)
	assert_true(ids.has(1))
	assert_true(ids.has(5))


func test_query_radius_all_within_large() -> void:
	_populate()
	var ids := _idx.query_radius(Vector2(0, 0), 200.0)
	assert_eq(ids.size(), 5)


func test_query_radius_negative_empty() -> void:
	_populate()
	var ids := _idx.query_radius(Vector2(0, 0), -1.0)
	assert_eq(ids.size(), 0)


func test_query_rect_finds_inside() -> void:
	_populate()
	var ids := _idx.query_rect(Rect2(-1, -1, 11, 11))
	# ids 1, 2, 5
	assert_eq(ids.size(), 3)
	assert_true(ids.has(1))
	assert_true(ids.has(2))
	assert_true(ids.has(5))


func test_query_nearest_k1() -> void:
	_populate()
	var ids := _idx.query_nearest(Vector2(0, 0), 1)
	assert_eq(ids.size(), 1)
	assert_true(ids[0] == 1 or ids[0] == 5)


func test_query_nearest_k3() -> void:
	_populate()
	var ids := _idx.query_nearest(Vector2(0, 0), 3)
	assert_eq(ids.size(), 3)
	# First two are 1 and 5 (at origin)
	var first_two := [ids[0], ids[1]]
	assert_true(first_two.has(1))
	assert_true(first_two.has(5))
	# Third is 2 (at 5,5)
	assert_eq(ids[2], 2)


func test_query_nearest_more_than_size() -> void:
	_populate()
	var ids := _idx.query_nearest(Vector2(0, 0), 100)
	assert_eq(ids.size(), 5)


func test_query_nearest_k0_empty() -> void:
	_populate()
	var ids := _idx.query_nearest(Vector2(0, 0), 0)
	assert_eq(ids.size(), 0)


# --- diagnostics ---

func test_bucket_count() -> void:
	_idx.insert(1, Vector2(0, 0))
	_idx.insert(2, Vector2(0.1, 0.1))  # same cell
	assert_eq(_idx.bucket_count(), 1)
	_idx.insert(3, Vector2(50, 50))  # different cell
	assert_eq(_idx.bucket_count(), 2)


func test_max_bucket_load() -> void:
	for i in range(5):
		_idx.insert(i, Vector2(0, 0))
	assert_eq(_idx.max_bucket_load(), 5)


func test_query_radius_deterministic() -> void:
	_populate()
	var r1 := _idx.query_radius(Vector2(0, 0), 50.0)
	var r2 := _idx.query_radius(Vector2(0, 0), 50.0)
	assert_eq(r1, r2)
