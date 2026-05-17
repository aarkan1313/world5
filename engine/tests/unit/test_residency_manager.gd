## Tests for ResidencyManager — diffs required pages vs cached, emits
## load/evict signals so the streaming layer can react.

extends GutTest


var _cache: TerrainPageCache
var _residency: ResidencyManager
var _loads_seen: Array = []
var _evicts_seen: Array = []


func before_each() -> void:
	_cache = TerrainPageCache.new()
	_cache.set_budget(10)
	_residency = ResidencyManager.new()
	_residency.configure(_cache, 256.0)  # page extent 256m
	_loads_seen = []
	_evicts_seen = []
	_residency.page_load_requested.connect(_on_load)
	_residency.page_evict_requested.connect(_on_evict)


func _on_load(ring: int, page_xz: Vector2) -> void:
	_loads_seen.append({"ring": ring, "xz": page_xz})


func _on_evict(ring: int, page_xz: Vector2) -> void:
	_evicts_seen.append({"ring": ring, "xz": page_xz})


# --- core diff behavior ---

func test_no_requirements_no_signals() -> void:
	_residency.update([])
	assert_eq(_loads_seen.size(), 0)
	assert_eq(_evicts_seen.size(), 0)


func test_requirement_for_missing_page_emits_load() -> void:
	var req: Array = [{"ring": 0, "xz": Vector2(0, 0)}]
	_residency.update(req)
	assert_eq(_loads_seen.size(), 1)
	assert_eq(_loads_seen[0]["ring"], 0)
	assert_eq(_loads_seen[0]["xz"], Vector2(0, 0))


func test_cached_requirement_emits_no_load() -> void:
	# Pre-populate cache
	var res: TerrainPageResult = TerrainPageResult.new()
	res.cache_key = "preloaded"
	_cache.put(0, Vector2(0, 0), res)

	_residency.update([{"ring": 0, "xz": Vector2(0, 0)}])
	assert_eq(_loads_seen.size(), 0, "already-cached page doesn't reload")


func test_dropped_requirement_emits_evict() -> void:
	# Prime the cache + record it as required
	var res: TerrainPageResult = TerrainPageResult.new()
	_cache.put(0, Vector2(0, 0), res)
	_residency.update([{"ring": 0, "xz": Vector2(0, 0)}])
	# Now requirement set becomes empty → previously-required page evicts
	_residency.update([])
	assert_eq(_evicts_seen.size(), 1)
	assert_eq(_evicts_seen[0]["xz"], Vector2(0, 0))


# --- multi-ring + multi-page diffs ---

func test_partial_overlap_loads_and_evicts() -> void:
	# Frame 1: require pages A, B
	_residency.update([
		{"ring": 0, "xz": Vector2(0, 0)},
		{"ring": 0, "xz": Vector2(256, 0)},
	])
	assert_eq(_loads_seen.size(), 2)
	# Simulate the load completing (populate cache)
	_cache.put(0, Vector2(0, 0), TerrainPageResult.new())
	_cache.put(0, Vector2(256, 0), TerrainPageResult.new())

	_loads_seen.clear()
	_evicts_seen.clear()

	# Frame 2: require B, C — A drops, C is new
	_residency.update([
		{"ring": 0, "xz": Vector2(256, 0)},
		{"ring": 0, "xz": Vector2(512, 0)},
	])
	assert_eq(_loads_seen.size(), 1, "only C is new")
	assert_eq(_loads_seen[0]["xz"], Vector2(512, 0))
	assert_eq(_evicts_seen.size(), 1, "A dropped")
	assert_eq(_evicts_seen[0]["xz"], Vector2(0, 0))


func test_required_pages_for_ring() -> void:
	# Camera at origin, ring extent 768m → footprint -384..+384
	# Pages 256m wide. Footprint covers page columns at x = -512, -256,
	# 0, 256 → 4 columns. Same Z → 4x4 = 16 pages.
	# (Ring is symmetric around camera so spans boundary between 0 and
	# negative-page columns; that's why it's 4x4 not 3x3.)
	var pages: Array = _residency.required_pages_for_ring(
		Vector2.ZERO, 0, 768.0)
	assert_eq(pages.size(), 16, "4x4 page grid for 768m centered ring")
	# Pages are page-origin-aligned
	for p in pages:
		var xz: Vector2 = p["xz"]
		assert_eq(int(xz.x) % 256, 0, "page x aligned to page boundary")
		assert_eq(int(xz.y) % 256, 0, "page y aligned to page boundary")


func test_camera_aligned_to_page_grid_yields_exact_count() -> void:
	# Camera at (128, 128) (page center for ring of 512m extent) — footprint
	# -128..+384 in X, -128..+384 in Z → 3x3 pages
	var pages: Array = _residency.required_pages_for_ring(
		Vector2(128.0, 128.0), 0, 512.0)
	assert_eq(pages.size(), 9, "3x3 when ring extent = exact page mult")


# --- idempotent updates ---

func test_repeated_update_with_same_set_emits_nothing() -> void:
	var req: Array = [{"ring": 0, "xz": Vector2(0, 0)}]
	_residency.update(req)
	# Pretend the page loaded
	_cache.put(0, Vector2(0, 0), TerrainPageResult.new())
	_loads_seen.clear()

	# Calling update with same set again should emit nothing
	_residency.update(req)
	assert_eq(_loads_seen.size(), 0)
	assert_eq(_evicts_seen.size(), 0)
