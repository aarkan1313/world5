## W5 JobScheduler — autoload that owns the WorkerThreadPool wrapping.
##
## Per spec 07. Single entry point for async CPU work; supports
## priority queue, dependency edges, cancellation, await_completion,
## and shutdown-safe drain.
##
## Also publishes its running + queued count to StreamingBudget as
## `active_jobs` (per spec 10 + audit S6; debounced to 100ms).
##
## Autoload at /root/JobScheduler (registered in Phase 2.12).

class_name JobScheduler extends Node

const SYSTEM_NAME: String = "job_scheduler"

# Shutdown flag — workers MUST check via is_shutting_down() and bail
var _shutting_down: bool = false

# Job registry (id -> Job)
var _jobs: Dictionary = {}
var _next_id: int = 1

# Priority queues (priority -> Array of pending job IDs)
var _queues: Dictionary = {
	Job.Priority.CRITICAL: [],
	Job.Priority.HIGH: [],
	Job.Priority.NORMAL: [],
	Job.Priority.LOW: [],
	Job.Priority.BACKGROUND: [],
}

# Currently running job IDs (in WorkerThreadPool)
var _running: Dictionary = {}  # job_id -> wtp_task_id

# Completed-job retention TTL (ms) before eviction
const _RESULT_EVICTION_TTL_MS: int = 60_000

# StreamingBudget debounce
var _last_publish_ms: int = 0
const _PUBLISH_DEBOUNCE_MS: int = 100


## Submit a job. Returns its assigned id. Runs when its dependencies
## complete + scheduler tick picks it up per priority.
func submit(job: Job) -> int:
	if job.id != -1:
		Log.warn(SYSTEM_NAME, "job already submitted", {"id": job.id, "name": job.name})
		return job.id
	job.id = _next_id
	_next_id += 1
	job.submitted_at_ms = Time.get_ticks_msec()
	_jobs[job.id] = job
	# Enqueue if no deps; else wait for deps to complete
	if _deps_satisfied(job):
		_queues[job.priority].append(job.id)
	_publish_to_budget()
	return job.id


## Query status of a job by id. Returns Job.Status enum; -1 if
## unknown id (e.g. already evicted).
func get_status(job_id: int) -> int:
	if not _jobs.has(job_id):
		return -1
	return _jobs[job_id].status


## Get the Job object by id. Returns null if not found (evicted).
func get_job(job_id: int) -> Job:
	return _jobs.get(job_id)


## Coroutine: yield until job completes; return result. Raises (via
## push_error) on FAILED or CANCELLED; result is null in those cases.
func await_completion(job_id: int) -> Variant:
	if not _jobs.has(job_id):
		Log.error(SYSTEM_NAME, "await_completion: unknown job id", {"id": job_id})
		return null
	var job: Job = _jobs[job_id]
	# Spin until done (yielding each frame)
	while not job.is_done():
		await get_tree().process_frame
		if _shutting_down:
			return null
	if job.status == Job.Status.FAILED:
		Log.error(SYSTEM_NAME, "job FAILED",
			{"id": job_id, "name": job.name, "error": job.error})
	if job.status == Job.Status.CANCELLED:
		Log.info(SYSTEM_NAME, "job cancelled", {"id": job_id, "name": job.name})
	return job.result


## Request cancellation of a job. Returns true if request was accepted
## (job was not yet done).
func cancel(job_id: int) -> bool:
	if not _jobs.has(job_id):
		return false
	var job: Job = _jobs[job_id]
	# If still pending in queue, remove + mark cancelled
	if job.status == Job.Status.PENDING:
		_queues[job.priority].erase(job_id)
		job.status = Job.Status.CANCELLED
		job.completed_at_ms = Time.get_ticks_msec()
		_publish_to_budget()
		return true
	# Otherwise cooperative cancel
	return job.request_cancel()


## Returns true if scheduler is shutting down (workers should bail).
func is_shutting_down() -> bool:
	return _shutting_down


## Diagnostic: per-priority pending count.
func get_queue_depth() -> Dictionary:
	var out := {}
	for p in _queues.keys():
		out[p] = _queues[p].size()
	return out


## Total queued (across all priorities).
func _get_queued_count() -> int:
	var total := 0
	for p in _queues.keys():
		total += _queues[p].size()
	return total


## Diagnostic: count of currently running jobs.
func get_running_count() -> int:
	return _running.size()


## Diagnostic: count of jobs that have completed (still in registry).
func get_total_completed() -> int:
	var count := 0
	for jid in _jobs.keys():
		if _jobs[jid].status == Job.Status.COMPLETED:
			count += 1
	return count


# --- Godot lifecycle ---

func _ready() -> void:
	Log.info(SYSTEM_NAME, "JobScheduler ready")


func _process(_delta: float) -> void:
	if _shutting_down:
		return
	_tick()


func _exit_tree() -> void:
	# Drain: signal shutdown, request cancel on every in-flight job,
	# wait for them to bail (cooperative; capped wait time)
	Log.info(SYSTEM_NAME, "JobScheduler shutting down — draining")
	_shutting_down = true
	for jid in _running.keys():
		var job: Job = _jobs.get(jid)
		if job != null:
			job.request_cancel()
	# WorkerThreadPool tasks are awaited in their own thread; we cannot
	# truly join here but the shutdown flag means _execute returns
	# quickly. Godot's WTP destructor will clean up.
	for jid in _running.keys():
		var wtp_id: int = _running[jid]
		if wtp_id != -1:
			WorkerThreadPool.wait_for_task_completion(wtp_id)
		# GpuJob (wtp_id == -1) runs synchronously on render thread; no wait needed
	_running.clear()


# --- internals ---

func _deps_satisfied(job: Job) -> bool:
	for dep_id in job.dependencies:
		if not _jobs.has(dep_id):
			# Dep doesn't exist (was evicted?); treat as satisfied to
			# avoid permanent stall
			continue
		var dep_job: Job = _jobs[dep_id]
		if dep_job.status != Job.Status.COMPLETED:
			return false
	return true


func _tick() -> void:
	# Move newly-ready jobs into queues (dep-satisfied)
	for jid in _jobs.keys():
		var job: Job = _jobs[jid]
		if job.status != Job.Status.PENDING:
			continue
		if job.id in _enumerate_all_queued():
			continue
		if _deps_satisfied(job):
			_queues[job.priority].append(jid)

	# Dispatch next priority-first job into WorkerThreadPool
	# (Simple: one dispatch per tick, prevents flooding WTP)
	for p in [Job.Priority.CRITICAL, Job.Priority.HIGH, Job.Priority.NORMAL,
			  Job.Priority.LOW, Job.Priority.BACKGROUND]:
		if _queues[p].size() > 0:
			var jid: int = _queues[p].pop_front()
			_dispatch(jid)
			break  # one per tick

	# Reap completed tasks (WTP for plain Job; render-thread for GpuJob)
	for jid in _running.keys():
		var wtp_id: int = _running[jid]
		var job: Job = _jobs[jid]
		if wtp_id == -1:
			# GpuJob: render thread runs synchronously per frame.
			# Check job status directly.
			if job.is_done():
				_running.erase(jid)
		else:
			if WorkerThreadPool.is_task_completed(wtp_id):
				WorkerThreadPool.wait_for_task_completion(wtp_id)
				_running.erase(jid)

	# Evict ancient terminal jobs
	var now := Time.get_ticks_msec()
	for jid in _jobs.keys():
		var job: Job = _jobs[jid]
		if job.is_done() and (now - job.completed_at_ms) > _RESULT_EVICTION_TTL_MS:
			_jobs.erase(jid)

	_publish_to_budget()


func _enumerate_all_queued() -> Array:
	var out: Array = []
	for p in _queues.keys():
		out.append_array(_queues[p])
	return out


func _dispatch(job_id: int) -> void:
	var job: Job = _jobs[job_id]
	if _shutting_down or job.is_cancelled():
		job.status = Job.Status.CANCELLED
		job.completed_at_ms = Time.get_ticks_msec()
		return
	# GpuJob routing per spec 08a: RenderingDevice calls must happen
	# on the render thread, NOT on WorkerThreadPool workers. GpuJob is
	# routed via RenderingServer.call_on_render_thread.
	if job is GpuJob:
		_running[job_id] = -1  # sentinel: GPU job, no WTP id
		RenderingServer.call_on_render_thread(Callable(job, "_run_on_render_thread"))
	else:
		# Plain Job goes to WorkerThreadPool
		var wtp_id := WorkerThreadPool.add_task(Callable(job, "_run"), false, job.name)
		_running[job_id] = wtp_id


var _streaming_budget_node: Node = null

func _publish_to_budget() -> void:
	var now := Time.get_ticks_msec()
	if (now - _last_publish_ms) < _PUBLISH_DEBOUNCE_MS:
		return
	_last_publish_ms = now
	# Lazy lookup so tests (which don't have /root/StreamingBudget)
	# silently no-op. Integration tests that instantiate both nodes
	# as siblings can set _streaming_budget_node directly via inject.
	if _streaming_budget_node == null:
		_streaming_budget_node = get_node_or_null("/root/StreamingBudget")
	if _streaming_budget_node != null:
		_streaming_budget_node.call("publish", SYSTEM_NAME,
			{"active_jobs": get_running_count() + _get_queued_count()})
