## PageStreamingJob — bridges ResidencyManager signals to
## TerrainBackendAdapter + writes results back to TerrainPageCache.
##
## Per spec 21 + plan doc Phase 4.4.b. Wires:
##   - ResidencyManager.page_load_requested → submit a backend job
##   - on job completion → cache.put + emit page_actually_loaded
##   - ResidencyManager.page_evict_requested → cache.evict
##
## Tracks in-flight jobs by (ring, xz) so duplicate load requests
## don't double-submit AND so ResidencyManager can query
## `has_in_flight()` to avoid re-emitting load_requested every frame
## (TR-INTEG-C3 fix).
##
## Node so it can connect signals + await coroutines + emit signals.

class_name PageStreamingJob extends Node


## Emitted AFTER a page actually lands in the cache (TR-INTEG-C3 fix).
## TerrainWorld relays this as its public `page_loaded` signal so
## consumers see real load events, not per-frame request spam.
signal page_actually_loaded(ring: int, page_xz: Vector2)
signal page_actually_evicted(ring: int, page_xz: Vector2)


var _adapter: TerrainBackendAdapter = null
var _cache: TerrainPageCache = null
# (ring, xz) -> int (job id), so duplicate loads are coalesced + so
# ResidencyManager can query has_in_flight() (TR-INTEG-C3)
var _inflight: Dictionary = {}

# Page generation params — fed from TerrainWorld at configure time
# (TR-INTEG-C1 fix: was hardcoded 256.0)
var _page_extent_m: float = 256.0
var _grid_n: int = 256
var _seed: int = 0
var _tier: String = "high"
var _kernel: NoiseStackKernel = null
var _capabilities: Array = ["height_cpu"]   # default — TR-SPEC-S3: callers can extend


func configure(adapter: TerrainBackendAdapter, cache: TerrainPageCache,
		page_extent_m: float = 256.0, grid_n: int = 256,
		seed: int = 0, tier: String = "high",
		kernel: NoiseStackKernel = null,
		capabilities: Array = ["height_cpu"]) -> void:
	_adapter = adapter
	_cache = cache
	_page_extent_m = page_extent_m
	_grid_n = grid_n
	_seed = seed
	_tier = tier
	_kernel = kernel
	_capabilities = capabilities


## Returns true iff a job is currently in flight for (ring, page_xz).
## Used by ResidencyManager (after Phase 4.4 audit fix) to skip
## re-emitting load_requested for in-flight pages.
func has_in_flight(ring: int, page_xz: Vector2) -> bool:
	return _inflight.has(_key(ring, page_xz))


## Signal handler for ResidencyManager.page_load_requested.
func on_load_requested(ring: int, page_xz: Vector2) -> void:
	if _adapter == null or _cache == null:
		return
	var k: String = _key(ring, page_xz)
	# Already in flight or already cached → no-op
	if _inflight.has(k) or _cache.has(ring, page_xz):
		return

	var req_dict := {
		"world_xz": page_xz,
		"extent_m": _page_extent_m,
		"grid_n": _grid_n,
		"seed": _seed,
		"tier": _tier,
		"capabilities": _capabilities,
	}
	if _kernel != null:
		req_dict["kernel"] = _kernel
	var req: TerrainPageRequest = TerrainPageRequest.from_dict(req_dict)
	var jid: int = _adapter.request_page(req)
	if jid <= 0:
		return
	_inflight[k] = jid
	_await_and_cache(k, ring, page_xz, jid)


## Signal handler for ResidencyManager.page_evict_requested.
func on_evict_requested(ring: int, page_xz: Vector2) -> void:
	if _cache == null:
		return
	if _cache.evict(ring, page_xz):
		_publish_budget()
		page_actually_evicted.emit(ring, page_xz)


# Publishes cache size + bytes to StreamingBudget after every change.
# Replaces the backend's monotonic high-water mark per TR-INTEG-C2 +
# matches spec 10 contract (publish current usage on residency change).
func _publish_budget() -> void:
	var budget: Node = get_node_or_null("/root/StreamingBudget")
	if budget == null or _cache == null:
		return
	budget.publish("terrain_cache", {
		"cpu_pages": _cache.size(),
		"resident_texture_mb": _cache.total_bytes() / (1024 * 1024),
	})


# --- internal ---

func _await_and_cache(k: String, ring: int, page_xz: Vector2,
		job_id: int) -> void:
	var scheduler: Node = get_node_or_null("/root/JobScheduler")
	if scheduler == null:
		_inflight.erase(k)
		return
	var res_raw: Variant = await scheduler.await_completion(job_id)
	_inflight.erase(k)
	if res_raw == null:
		return
	var res: TerrainPageResult = res_raw as TerrainPageResult
	if res == null or not res.has_capability("height_cpu"):
		return
	_cache.put(ring, page_xz, res)
	_publish_budget()
	# Emit AFTER successful cache write — this is the "actually loaded"
	# moment per TR-INTEG-C3 fix.
	page_actually_loaded.emit(ring, page_xz)


func _key(ring: int, page_xz: Vector2) -> String:
	return "%d:%d:%d" % [ring, int(page_xz.x), int(page_xz.y)]
