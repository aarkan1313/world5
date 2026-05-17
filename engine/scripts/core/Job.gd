## W5 Job base class — wraps WorkerThreadPool tasks with priority,
## cancellation, dependencies, and shutdown-safe drain.
##
## Per spec 07. Every async CPU op in W5 subclasses this. Direct
## WorkerThreadPool.add_task calls are forbidden (Phase 2.11 lint
## catches violators).
##
## Override _execute() to do your work. MUST check
## JobScheduler.is_shutting_down() periodically + return early so the
## scheduler can drain cleanly.

class_name Job extends RefCounted

enum Priority { CRITICAL, HIGH, NORMAL, LOW, BACKGROUND }
enum Status { PENDING, RUNNING, COMPLETED, FAILED, CANCELLED }

# Assigned by JobScheduler.submit
var id: int = -1
var name: String = "unnamed_job"
var priority: Priority = Priority.NORMAL
var status: Status = Status.PENDING
var dependencies: Array[int] = []
var result: Variant = null
var error: String = ""

# Optional metadata for diagnostics + per-instance throttling
var submitted_at_ms: int = 0
var started_at_ms: int = 0
var completed_at_ms: int = 0
var _cancellation_requested: bool = false


## Override: do the work. Return the result variant. Set self.error
## + return null on failure (or just raise via push_error). MUST
## check is_cancelled() + JobScheduler.is_shutting_down()
## periodically and return null early.
func _execute() -> Variant:
	Log.error("job", "Job._execute() must be overridden in subclass", {"name": name})
	return null


## Internal: scheduler calls this. Do not override.
func _run() -> void:
	started_at_ms = Time.get_ticks_msec()
	status = Status.RUNNING
	if _cancellation_requested:
		status = Status.CANCELLED
		completed_at_ms = Time.get_ticks_msec()
		return
	# Call subclass implementation
	var r: Variant = _execute()
	completed_at_ms = Time.get_ticks_msec()
	if _cancellation_requested:
		status = Status.CANCELLED
		return
	if error != "":
		status = Status.FAILED
		return
	result = r
	status = Status.COMPLETED


## Request cancellation. Cooperative: the running _execute() must
## check is_cancelled() periodically + return early. Returns true
## if cancellation was requested in time (status was PENDING or
## RUNNING when called).
func request_cancel() -> bool:
	if status in [Status.COMPLETED, Status.FAILED, Status.CANCELLED]:
		return false
	_cancellation_requested = true
	return true


## Inside _execute(): check if cancellation was requested.
func is_cancelled() -> bool:
	return _cancellation_requested


## True when job has reached a terminal state.
func is_done() -> bool:
	return status in [Status.COMPLETED, Status.FAILED, Status.CANCELLED]


## Returns duration in ms from start to completion (0 if not done).
func duration_ms() -> int:
	if started_at_ms == 0:
		return 0
	if completed_at_ms == 0:
		return Time.get_ticks_msec() - started_at_ms
	return completed_at_ms - started_at_ms
