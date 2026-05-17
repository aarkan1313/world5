## W5 AssetStream — autoload wrapping ResourceLoader.load_threaded_*.
##
## Per spec 09. Every async asset load in W5 goes through here.
## Provides:
## - Request/await with priority + dedup (same path in flight = same req id)
## - In-memory cache with LRU eviction past budget
## - Type adapters (request_mesh extracts ArrayMesh from PackedScene GLBs)
## - StreamingBudget integration (publishes asset_cache_mb)
##
## Autoload at /root/AssetStream (registered Phase 2.12).

class_name AssetStream extends Node

const SYSTEM_NAME: String = "asset_stream"

enum Status { NOT_LOADED, LOADING, READY, FAILED }
enum Priority { CRITICAL, HIGH, NORMAL, LOW, BACKGROUND }

# Internal request record
class _Request:
	var id: int
	var path: String
	var priority: int = Priority.NORMAL
	var status: int = Status.NOT_LOADED
	var resource: Resource = null
	var error: String = ""
	var adapter: String = ""  # "" | "mesh" | "texture" | future adapters
	var size_bytes: int = 0  # estimated; populated on READY

# id → _Request
var _requests: Dictionary = {}
# path → req_id (dedup in-flight by path)
var _path_to_id: Dictionary = {}
var _next_id: int = 1

# LRU cache: path → resource (READY only); access order tracked via _lru
var _cache: Dictionary = {}
var _lru: Array[String] = []  # least-recent-first

# Per-system bytes for budget reporting
var _cache_bytes: int = 0
var _cache_budget_bytes: int = 800 * 1024 * 1024  # default; QualityTiers overrides

# Debounce StreamingBudget publishes
var _last_publish_ms: int = 0
const _PUBLISH_DEBOUNCE_MS: int = 100


# --- request ---

## Begin loading `path`. Returns a request ID. Idempotent — requesting
## the same path returns the same ID while the original is in flight or
## cached.
func request(path: String, priority: int = Priority.NORMAL) -> int:
	# Cache hit → synthesize a READY request entry
	if _cache.has(path):
		_touch_lru(path)
		# Return existing id if there is one; otherwise create a new
		# entry pointing at the cached resource.
		if _path_to_id.has(path):
			return _path_to_id[path]
		var req := _make_request(path, priority)
		req.status = Status.READY
		req.resource = _cache[path]
		return req.id
	# In-flight dedup
	if _path_to_id.has(path):
		return _path_to_id[path]
	# Fresh request
	var new_req := _make_request(path, priority)
	new_req.status = Status.LOADING
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		new_req.status = Status.FAILED
		new_req.error = "load_threaded_request returned %d" % err
		Log.error(SYSTEM_NAME, "request failed at submit",
			{"path": path, "err": err})
	return new_req.id


## Type adapter: request a Mesh. If `path` is a GLB / scene file, the
## adapter extracts the first MeshInstance3D's Mesh from the PackedScene
## (W4 R14d-1 pattern). Returns same ID semantics as request().
func request_mesh(path: String, priority: int = Priority.NORMAL) -> int:
	var rid := request(path, priority)
	if _requests.has(rid):
		_requests[rid].adapter = "mesh"
	return rid


# --- query ---

func get_status(req_id: int) -> int:
	if not _requests.has(req_id):
		return Status.NOT_LOADED
	return _requests[req_id].status


func get_resource(req_id: int) -> Resource:
	if not _requests.has(req_id):
		return null
	return _requests[req_id].resource


func get_error(req_id: int) -> String:
	if not _requests.has(req_id):
		return ""
	return _requests[req_id].error


func is_ready(path: String) -> bool:
	return _cache.has(path)


func get_cached(path: String) -> Resource:
	if not _cache.has(path):
		return null
	_touch_lru(path)
	return _cache[path]


# --- await ---

## Coroutine: yield until status is READY. Returns the resource (null
## on FAILED — caller checks get_error).
func await_ready(req_id: int) -> Resource:
	if not _requests.has(req_id):
		push_error("await_ready: unknown req id %d" % req_id)
		return null
	var req: _Request = _requests[req_id]
	while req.status == Status.LOADING or req.status == Status.NOT_LOADED:
		await get_tree().process_frame
	if req.status == Status.FAILED:
		Log.error(SYSTEM_NAME, "await_ready: FAILED",
			{"path": req.path, "error": req.error})
		return null
	return req.resource


# --- cancellation + eviction ---

func cancel(req_id: int) -> bool:
	if not _requests.has(req_id):
		return false
	var req: _Request = _requests[req_id]
	if req.status != Status.LOADING:
		return false
	# Godot's ResourceLoader doesn't expose cancel; mark our wrapper
	# cancelled + drop the resource when it eventually arrives.
	req.status = Status.FAILED
	req.error = "cancelled"
	_path_to_id.erase(req.path)
	return true


func evict(path: String) -> bool:
	if not _cache.has(path):
		return false
	var res: Resource = _cache[path]
	# Refcount check: if anyone else holds a ref, the resource survives
	# our erase + GC kicks it later. Either way we drop our cache entry.
	_cache_bytes -= _estimate_bytes(res)
	if _cache_bytes < 0:
		_cache_bytes = 0
	_cache.erase(path)
	_lru.erase(path)
	return true


func set_cache_budget_mb(mb: int) -> void:
	_cache_budget_bytes = mb * 1024 * 1024
	_enforce_budget()


func get_cache_usage_mb() -> int:
	return int(_cache_bytes / (1024 * 1024))


# --- diagnostics ---

func get_in_flight_count() -> int:
	var n := 0
	for rid in _requests.keys():
		if _requests[rid].status == Status.LOADING:
			n += 1
	return n


func get_cache_count() -> int:
	return _cache.size()


func get_stats() -> Dictionary:
	return {
		"in_flight": get_in_flight_count(),
		"cached": _cache.size(),
		"cache_bytes": _cache_bytes,
		"cache_budget_bytes": _cache_budget_bytes,
		"requests_total": _requests.size(),
	}


# --- Godot lifecycle ---

func _ready() -> void:
	Log.info(SYSTEM_NAME, "AssetStream ready")


func _process(_delta: float) -> void:
	_tick()


# --- internals ---

func _make_request(path: String, priority: int) -> _Request:
	var req := _Request.new()
	req.id = _next_id
	_next_id += 1
	req.path = path
	req.priority = priority
	_requests[req.id] = req
	_path_to_id[path] = req.id
	return req


func _tick() -> void:
	# Poll each LOADING request for completion
	for rid in _requests.keys():
		var req: _Request = _requests[rid]
		if req.status != Status.LOADING:
			continue
		var godot_status := ResourceLoader.load_threaded_get_status(req.path)
		match godot_status:
			ResourceLoader.THREAD_LOAD_LOADED:
				_promote_to_ready(req)
			ResourceLoader.THREAD_LOAD_FAILED:
				req.status = Status.FAILED
				req.error = "load_threaded_get_status FAILED"
				_path_to_id.erase(req.path)
				Log.error(SYSTEM_NAME, "load FAILED", {"path": req.path})
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				req.status = Status.FAILED
				req.error = "INVALID_RESOURCE"
				_path_to_id.erase(req.path)
				Log.error(SYSTEM_NAME, "load INVALID",
					{"path": req.path})
			# IN_PROGRESS → keep polling
	_publish_to_budget()


func _promote_to_ready(req: _Request) -> void:
	var raw := ResourceLoader.load_threaded_get(req.path)
	if raw == null:
		req.status = Status.FAILED
		req.error = "load_threaded_get returned null"
		_path_to_id.erase(req.path)
		return
	# Apply adapter
	var resource: Resource = raw
	if req.adapter == "mesh":
		resource = _extract_mesh_from_scene(raw)
		if resource == null:
			req.status = Status.FAILED
			req.error = "mesh adapter: no MeshInstance3D in PackedScene"
			Log.error(SYSTEM_NAME, "mesh adapter failed",
				{"path": req.path})
			_path_to_id.erase(req.path)
			return
	req.resource = resource
	req.status = Status.READY
	req.size_bytes = _estimate_bytes(resource)
	_cache[req.path] = resource
	_touch_lru(req.path)
	_cache_bytes += req.size_bytes
	_enforce_budget()


func _extract_mesh_from_scene(raw: Resource) -> Mesh:
	## Per W4 R14d-1: GLB loads as PackedScene; we want the
	## ArrayMesh of the first MeshInstance3D.
	if raw is Mesh:
		return raw
	if raw is PackedScene:
		var instantiated: Node = raw.instantiate()
		if instantiated == null:
			return null
		var mesh: Mesh = _find_mesh_in_node(instantiated)
		instantiated.queue_free()
		return mesh
	return null


func _find_mesh_in_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _find_mesh_in_node(child)
		if found != null:
			return found
	return null


func _estimate_bytes(res: Resource) -> int:
	## Best-effort size estimate. Real measurement requires per-type
	## inspection; for now we use rough heuristics.
	if res is Mesh:
		var mesh := res as Mesh
		var total := 0
		for i in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(i)
			if arrays.size() > Mesh.ARRAY_VERTEX:
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				total += verts.size() * 12  # 3 floats per vertex
		return max(total, 1024)  # min 1KB so cache accounting tracks
	if res is Texture2D:
		var tex := res as Texture2D
		return tex.get_width() * tex.get_height() * 4  # RGBA8 estimate
	return 4096  # default 4KB for unknown types


func _touch_lru(path: String) -> void:
	_lru.erase(path)
	_lru.append(path)  # most-recent at end


func _enforce_budget() -> void:
	while _cache_bytes > _cache_budget_bytes and _lru.size() > 0:
		var oldest: String = _lru[0]
		evict(oldest)


var _streaming_budget_node: Node = null

func _publish_to_budget() -> void:
	var now := Time.get_ticks_msec()
	if (now - _last_publish_ms) < _PUBLISH_DEBOUNCE_MS:
		return
	_last_publish_ms = now
	if _streaming_budget_node == null:
		_streaming_budget_node = get_node_or_null("/root/StreamingBudget")
	if _streaming_budget_node != null:
		_streaming_budget_node.call("publish", SYSTEM_NAME,
			{"asset_cache_mb": get_cache_usage_mb()})


## Test helper: clear all state.
func _reset() -> void:
	_requests.clear()
	_path_to_id.clear()
	_cache.clear()
	_lru.clear()
	_cache_bytes = 0
	_next_id = 1
