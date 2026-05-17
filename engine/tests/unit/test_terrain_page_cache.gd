## Tests for TerrainPageCache — LRU page cache keyed by (ring, xz).

extends GutTest


func _mk_result(ring: int, xz: Vector2) -> TerrainPageResult:
	# Minimal populated result — backend would normally produce these
	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": xz, "extent_m": 256.0, "grid_n": 8,
		"seed": 0, "tier": "high", "capabilities": ["height_cpu"],
	})
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = req
	res.height_cpu = PackedFloat32Array()
	res.height_cpu.resize(8 * 8)
	res.cache_key = "key_%d_%d_%d" % [ring, int(xz.x), int(xz.y)]
	return res


func test_constructible() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	assert_eq(cache.size(), 0)
	assert_eq(cache.budget, 0, "default budget = 0 (unbounded until set)")


func test_put_and_get() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(10)
	var res: TerrainPageResult = _mk_result(0, Vector2(100.0, 200.0))
	cache.put(0, Vector2(100.0, 200.0), res)
	assert_eq(cache.size(), 1)
	assert_true(cache.has(0, Vector2(100.0, 200.0)))
	var got: TerrainPageResult = cache.get_page(0, Vector2(100.0, 200.0))
	assert_eq(got, res, "same instance returned")


func test_miss_returns_null() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(10)
	assert_null(cache.get_page(0, Vector2.ZERO))
	assert_false(cache.has(0, Vector2.ZERO))


func test_different_rings_separate_keys() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(10)
	var r0: TerrainPageResult = _mk_result(0, Vector2.ZERO)
	var r1: TerrainPageResult = _mk_result(1, Vector2.ZERO)
	cache.put(0, Vector2.ZERO, r0)
	cache.put(1, Vector2.ZERO, r1)
	assert_eq(cache.size(), 2)
	assert_eq(cache.get_page(0, Vector2.ZERO), r0)
	assert_eq(cache.get_page(1, Vector2.ZERO), r1)


# --- LRU eviction ---

func test_lru_evicts_oldest_at_budget() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(3)
	cache.put(0, Vector2(0, 0), _mk_result(0, Vector2(0, 0)))
	cache.put(0, Vector2(1, 0), _mk_result(0, Vector2(1, 0)))
	cache.put(0, Vector2(2, 0), _mk_result(0, Vector2(2, 0)))
	assert_eq(cache.size(), 3)
	# Adding a 4th evicts the oldest (0,0)
	cache.put(0, Vector2(3, 0), _mk_result(0, Vector2(3, 0)))
	assert_eq(cache.size(), 3)
	assert_false(cache.has(0, Vector2(0, 0)),
		"oldest (0,0) evicted")
	assert_true(cache.has(0, Vector2(3, 0)))


func test_get_promotes_lru() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(3)
	cache.put(0, Vector2(0, 0), _mk_result(0, Vector2(0, 0)))
	cache.put(0, Vector2(1, 0), _mk_result(0, Vector2(1, 0)))
	cache.put(0, Vector2(2, 0), _mk_result(0, Vector2(2, 0)))
	# Access (0,0) — now it's most-recent
	cache.get_page(0, Vector2(0, 0))
	# Insert (3,0) — should evict (1,0), not (0,0)
	cache.put(0, Vector2(3, 0), _mk_result(0, Vector2(3, 0)))
	assert_true(cache.has(0, Vector2(0, 0)), "promoted entry retained")
	assert_false(cache.has(0, Vector2(1, 0)), "next-oldest evicted")


# --- explicit evict ---

func test_explicit_evict() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(10)
	cache.put(0, Vector2.ZERO, _mk_result(0, Vector2.ZERO))
	assert_true(cache.evict(0, Vector2.ZERO))
	assert_eq(cache.size(), 0)
	assert_false(cache.evict(0, Vector2.ZERO),
		"evicting missing returns false")


func test_clear() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(10)
	for i in range(5):
		cache.put(0, Vector2(i, 0), _mk_result(0, Vector2(i, 0)))
	cache.clear()
	assert_eq(cache.size(), 0)


# --- StreamingBudget integration ---

func test_total_bytes_tracked() -> void:
	var cache: TerrainPageCache = TerrainPageCache.new()
	cache.set_budget(10)
	var r: TerrainPageResult = _mk_result(0, Vector2.ZERO)
	cache.put(0, Vector2.ZERO, r)
	# 8x8 floats = 256 bytes per page
	assert_eq(cache.total_bytes(), 256)
	# Evict drops the byte count
	cache.evict(0, Vector2.ZERO)
	assert_eq(cache.total_bytes(), 0)
