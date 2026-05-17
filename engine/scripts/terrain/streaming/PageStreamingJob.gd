## PageStreamingJob — bridges ResidencyManager signals to
## TerrainBackendAdapter + writes results back to TerrainPageCache.
##
## Per spec 21 + plan doc Phase 4.4.b. Wires:
##   - ResidencyManager.page_load_requested → submit a backend job
##   - on job completion → cache.put
##   - ResidencyManager.page_evict_requested → cache.evict
##
## Tracks in-flight jobs by (ring, xz) so duplicate load requests
## don't double-submit. Drops cache writes for cancelled/failed jobs.
##
## Node so it can connect signals + await coroutines.

class_name PageStreamingJob extends Node


var _adapter: TerrainBackendAdapter = null
var _cache: TerrainPageCache = null
# (ring, xz) -> int (job id), so duplicate loads are coalesced
var _inflight: Dictionary = {}
# Default capabilities the streaming layer requests. Renderer + sampler
# both need height_cpu in Phase 4 (height_gpu lands when renderer's
# vertex shader consumes it).
var _default_capabilities: Array = ["height_cpu"]


func configure(adapter: TerrainBackendAdapter, cache: TerrainPageCache) -> void:
	_adapter = adapter
	_cache = cache


## Signal handler for ResidencyManager.page_load_requested.
func on_load_requested(ring: int, page_xz: Vector2) -> void:
	if _adapter == null or _cache == null:
		return
	var k: String = _key(ring, page_xz)
	# Already in flight or already cached → no-op
	if _inflight.has(k) or _cache.has(ring, page_xz):
		return

	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": page_xz,
		"extent_m": 256.0,    # spec 20 page extent default
		"grid_n": 256,
		"seed": 0,
		"tier": "high",
		"capabilities": _default_capabilities,
	})
	var jid: int = _adapter.request_page(req)
	if jid <= 0:
		return
	_inflight[k] = jid
	_await_and_cache(k, ring, page_xz, jid)


## Signal handler for ResidencyManager.page_evict_requested.
func on_evict_requested(ring: int, page_xz: Vector2) -> void:
	if _cache == null:
		return
	_cache.evict(ring, page_xz)


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


func _key(ring: int, page_xz: Vector2) -> String:
	return "%d:%d:%d" % [ring, int(page_xz.x), int(page_xz.y)]
