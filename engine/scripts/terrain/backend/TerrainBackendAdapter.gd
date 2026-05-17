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

# Last-submitted job id, used to serialize page generation behind itself
# (TB-REV-C1: each page generation does rd.submit() + rd.sync() which
# blocks the render thread; capping concurrent in-flight pages at 1
# bounds the per-frame stall to one page until Phase 4.4's
# ResidencyManager + async readback split the work across frames).
var _last_job_id: int = -1


func _init() -> void:
	_backend = GpuTerrainBackend.new()


## Owner MUST call before drop, OR before RenderingDevice teardown
## (per spec 08a rule 5; TB-REV-C2). Idempotent.
func shutdown() -> void:
	if _backend != null:
		_backend.shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _backend != null:
			shutdown()


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
	# Serialize: this job depends on the previous one finishing so the
	# render thread only stalls on one page at a time. Drops the dep
	# if the previous job has already completed (scheduler treats
	# unknown ids as satisfied).
	if _last_job_id != -1:
		job.dependencies = [_last_job_id]
	var jid: int = scheduler.submit(job)
	_last_job_id = jid
	return jid


func _get_scheduler() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null("/root/JobScheduler")


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
			var sched: Node = loop.root.get_node_or_null("/root/JobScheduler")
			if sched != null and sched.is_shutting_down():
				return null
		if backend == null or request == null:
			error = "TerrainPageJob: backend or request missing"
			return null
		return backend.generate_page(request)
