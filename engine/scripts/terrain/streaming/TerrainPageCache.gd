## TerrainPageCache — LRU cache of TerrainPageResult, keyed by
## (ring_index, page_xz).
##
## Per spec 21 + plan doc Phase 4.4.b. The ResidencyManager decides
## which pages to request + evict; this class just holds them in an
## LRU bounded by `budget` entries (set via set_budget; 0 = unbounded).
##
## Why string keys? Dictionary doesn't hash `(int, Vector2)` tuples
## natively. We encode as "<ring>:<x>:<z>" — simple, deterministic,
## hashable. Page XZ is integer-aligned (page origin in world meters)
## so encoding to int is lossless for the use case.

class_name TerrainPageCache extends RefCounted


## Max number of pages retained. 0 = unbounded. Set via set_budget.
var budget: int = 0

# Internal state
var _entries: Dictionary = {}   # key (String) -> TerrainPageResult
var _lru_order: Array = []      # keys in LRU order: front = oldest


# --- public API ---

func set_budget(max_pages: int) -> void:
	budget = max(0, max_pages)
	_enforce_budget()


func size() -> int:
	return _entries.size()


func has(ring: int, page_xz: Vector2) -> bool:
	return _entries.has(_key(ring, page_xz))


func put(ring: int, page_xz: Vector2, result: TerrainPageResult) -> void:
	var k: String = _key(ring, page_xz)
	if _entries.has(k):
		_lru_order.erase(k)
	_entries[k] = result
	_lru_order.append(k)
	_enforce_budget()


## Returns the cached result + promotes it in the LRU. Returns null
## if missing.
func get_page(ring: int, page_xz: Vector2) -> TerrainPageResult:
	var k: String = _key(ring, page_xz)
	if not _entries.has(k):
		return null
	# Promote: move to end (most-recent)
	_lru_order.erase(k)
	_lru_order.append(k)
	return _entries[k]


## Returns true iff something was removed.
func evict(ring: int, page_xz: Vector2) -> bool:
	var k: String = _key(ring, page_xz)
	if not _entries.has(k):
		return false
	_free_gpu_rids(_entries[k])
	_entries.erase(k)
	_lru_order.erase(k)
	return true


func clear() -> void:
	for res in _entries.values():
		_free_gpu_rids(res)
	_entries.clear()
	_lru_order.clear()


# Free any GPU RIDs the TerrainPageResult owns + unregister with the
# tracker. Today only height_cpu is populated (Phase 4.4 scope) so
# this is mostly no-op; lights up when Phase 4.5+ delivers
# height_gpu / biome_mask_gpu / drainage_map per spec 20 capabilities.
# Audit S1 fix: was a silent GPU leak path the moment GPU caps land.
func _free_gpu_rids(res: TerrainPageResult) -> void:
	if res == null:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		return
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	var tracker: Node = null
	if loop != null:
		tracker = W5Lookup.find("GpuResourceTracker")
	for rid in [res.height_gpu, res.biome_mask_gpu, res.drainage_map]:
		if rid.is_valid():
			rd.free_rid(rid)
			if tracker != null:
				tracker.unregister(rid)


## Approximate total CPU-page bytes held. Used by StreamingBudget
## publishing (Phase 4.4 wires this into ResidencyManager).
func total_bytes() -> int:
	var sum: int = 0
	for r in _entries.values():
		var res: TerrainPageResult = r
		sum += res.height_cpu.size() * 4  # float32
		# Other CPU caps add bytes too; height dominates for Phase 4
		sum += res.slope.size() * 4
		sum += res.collision_height.size() * 4
		sum += res.nav_traversability.size()
		sum += res.biome_mask_cpu.size()
	return sum


# --- internals ---

func _key(ring: int, page_xz: Vector2) -> String:
	return "%d:%d:%d" % [ring, int(page_xz.x), int(page_xz.y)]


func _enforce_budget() -> void:
	if budget <= 0:
		return
	# Drop oldest until we're under budget. Decrement count as we go
	# (the while loop's check was on _entries.size() which didn't
	# shrink inside the loop body — bug fixed: now we account properly).
	var over: int = _entries.size() - budget
	while over > 0 and _lru_order.size() > 0:
		var k: String = _lru_order[0]
		_lru_order.pop_front()
		# Free GPU RIDs before dropping the result (audit S1 fix)
		_free_gpu_rids(_entries[k])
		_entries.erase(k)
		over -= 1
