## TerrainBackendAdapter — public facade for terrain page generation.
##
## Per spec 20: this is THE entry point consumers use. Wraps the
## GpuTerrainBackend in a GpuJob submitted via JobScheduler so that
## RenderingDevice calls happen on the render thread (spec 08a rule 1).
##
## Usage:
##   var adapter := TerrainBackendAdapter.new()
##   var job_id := adapter.request_page(request)
##   var result: TerrainPageResult = await JobScheduler.await_completion(job_id)
##
## The adapter does NOT cache results — that's the renderer's
## TerrainPageCache module (Phase 4.4). The adapter is a pure
## request-to-job translator.

class_name TerrainBackendAdapter extends RefCounted


# Singleton backend reused across requests (compiles shader once)
var _backend: GpuTerrainBackend = null

# Bounded-concurrency window for page generation. Each page does
# rd.submit() + rd.sync() on the render thread (~2-10ms each). Strict
# serialization (window=1) was Phase 4.4's defensive default + auditor
# called out the perf cost. Phase 4.5 raises to 4 — render thread
# still serializes the calls, but the JobScheduler scheduling latency
# (1 page per scheduler tick) is amortized.
#
# Acts as a circular buffer of recent job ids — each new job depends
# on the (N-th oldest) job in the window so at most max_in_flight
# pages are unfinished at any time.
var _in_flight_window: Array = []          # Array[int] (job ids)
var _max_in_flight: int = 4


func _init() -> void:
	_backend = GpuTerrainBackend.new()


## Owner MUST call before drop, OR before RenderingDevice teardown
## (per spec 08a rule 5; TB-REV-C2). Idempotent.
func shutdown() -> void:
	# Capture local ref + null the field first so a re-entrant
	# notification (e.g. when this adapter's own PREDELETE fires
	# during a shutdown chain) sees null and bails.
	var backend: GpuTerrainBackend = _backend
	_backend = null
	if backend != null and is_instance_valid(backend):
		backend.shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Inline the shutdown logic (calling shutdown() here triggers a
		# "null instance" warning under late-stage RefCounted PREDELETE
		# because the GDScript dispatch sees self as mid-deallocation
		# even though it's running on us). The actual work is just:
		var backend: GpuTerrainBackend = _backend
		_backend = null
		if backend != null and is_instance_valid(backend):
			backend.shutdown()


## Register a DemSource on the underlying backend so dem_feature
## chain stages can look it up by ID. Owner (TerrainWorld) calls
## this at bundle load for each DEM in `<bundle>/dem/`. Idempotent.
func register_dem_source(source_id: String, source: Object) -> void:
	if _backend == null:
		return
	_backend.register_dem_source(source_id, source)


## Clear all registered DEM sources. Called on bundle unload.
func clear_dem_sources() -> void:
	if _backend == null:
		return
	_backend.clear_dem_sources()


## Submit a page-generation request. Returns the JobScheduler job id.
## Consumer awaits completion via JobScheduler.await_completion(id).
## Returns -1 if JobScheduler autoload is not available.
func request_page(request: TerrainPageRequest) -> int:
	var scheduler: Node = _get_scheduler()
	if scheduler == null:
		Log.error("terrain_backend", "JobScheduler autoload missing", {})
		return -1
	var job: _TerrainPageJob = _TerrainPageJob.new()
	job.backend = _backend
	job.request = request
	job.name = "terrain_page_%s" % request.cache_key().substr(0, 8)
	job.priority = Job.Priority.NORMAL
	# Bounded concurrency: if the window is full, this job depends on
	# the oldest job in the window. When that one completes, this one
	# unblocks. Result: at most max_in_flight pages in flight at once.
	# (Phase 4.5 TR-PERF-C2 fix; was strict serialization in Phase 4.4.)
	if _in_flight_window.size() >= _max_in_flight:
		var oldest: int = _in_flight_window[0]
		_in_flight_window.pop_front()
		job.dependencies = [oldest]
	var jid: int = scheduler.submit(job)
	_in_flight_window.append(jid)
	return jid


## Configure the in-flight window. Defaults to 4 (Phase 4.5 sweet
## spot for 4-ring renderer). Set to 1 for strict serialization
## (Phase 4.4 behavior, useful for debugging).
func set_max_in_flight(n: int) -> void:
	_max_in_flight = max(1, n)


func _get_scheduler() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return W5Lookup.find("JobScheduler")


# --- Inner job class: runs the backend on the render thread ---
#
# Inner class instead of separate file because (a) it's an
# implementation detail of the adapter, (b) keeps the file count
# manageable, (c) the backend is already its own class.

class _TerrainPageJob extends GpuJob:
	var backend: GpuTerrainBackend = null
	var request: TerrainPageRequest = null

	func _execute() -> Variant:
		if is_cancelled():
			return null
		# Check shutdown via autoload instance (class_name is a type,
		# not the running node)
		var loop: SceneTree = Engine.get_main_loop() as SceneTree
		if loop != null:
			var sched: Node = W5Lookup.find("JobScheduler")
			if sched != null and sched.is_shutting_down():
				return null
		if backend == null or request == null:
			error = "TerrainPageJob: backend or request missing"
			return null
		return backend.generate_page(request)
