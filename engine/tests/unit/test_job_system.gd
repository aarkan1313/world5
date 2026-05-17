## Tests for Job + JobScheduler.
##
## Per spec 07. JobScheduler is meant to be an autoload but for unit
## tests we instance it manually as a child of the test scene.

extends GutTest


# Simple test Job subclass that returns a fixed value
class _SimpleJob extends Job:
	var _output: int

	func _init(out: int):
		_output = out
		name = "simple_job_%d" % out

	func _execute() -> Variant:
		return _output


# Job that errors out
class _ErroringJob extends Job:
	func _init():
		name = "erroring_job"

	func _execute() -> Variant:
		error = "intentional test error"
		return null


# Job that sleeps then checks cancellation cooperatively
class _CooperativeJob extends Job:
	var sleep_ms: int = 100

	func _init(ms: int = 100):
		sleep_ms = ms
		name = "cooperative_job"

	func _execute() -> Variant:
		var start := Time.get_ticks_msec()
		while (Time.get_ticks_msec() - start) < sleep_ms:
			if is_cancelled():
				return null
			OS.delay_msec(5)
		return "completed"


var _scheduler: JobScheduler


func before_each() -> void:
	_scheduler = JobScheduler.new()
	add_child_autofree(_scheduler)


# --- Job class tests ---

func test_job_default_status_pending() -> void:
	var job := _SimpleJob.new(42)
	assert_eq(job.status, Job.Status.PENDING)


func test_job_priority_default_normal() -> void:
	var job := _SimpleJob.new(42)
	assert_eq(job.priority, Job.Priority.NORMAL)


func test_job_request_cancel_marks_pending() -> void:
	var job := _SimpleJob.new(42)
	assert_true(job.request_cancel())
	assert_true(job.is_cancelled())


func test_job_is_done_false_initially() -> void:
	var job := _SimpleJob.new(42)
	assert_false(job.is_done())


# --- JobScheduler tests ---

func test_submit_assigns_id() -> void:
	var job := _SimpleJob.new(42)
	var jid := _scheduler.submit(job)
	assert_ne(jid, -1)
	assert_eq(job.id, jid)


func test_submit_twice_warns_returns_same_id() -> void:
	var job := _SimpleJob.new(42)
	var jid1 := _scheduler.submit(job)
	var jid2 := _scheduler.submit(job)
	assert_eq(jid1, jid2)


func test_get_status_unknown_returns_minus_one() -> void:
	assert_eq(_scheduler.get_status(99999), -1)


func test_get_job_returns_job() -> void:
	var job := _SimpleJob.new(42)
	var jid := _scheduler.submit(job)
	var retrieved := _scheduler.get_job(jid)
	assert_eq(retrieved, job)


func test_await_completion_returns_result() -> void:
	var job := _SimpleJob.new(99)
	var jid := _scheduler.submit(job)
	var result = await _scheduler.await_completion(jid)
	assert_eq(result, 99)
	assert_eq(job.status, Job.Status.COMPLETED)


func test_erroring_job_marked_failed() -> void:
	var job := _ErroringJob.new()
	var jid := _scheduler.submit(job)
	# Suppress expected push_error from await_completion's reporting
	await _scheduler.await_completion(jid)
	assert_eq(job.status, Job.Status.FAILED)
	assert_eq(job.error, "intentional test error")


func test_cancel_pending_job() -> void:
	var job := _SimpleJob.new(42)
	job.priority = Job.Priority.LOW  # less likely to dispatch immediately
	var jid := _scheduler.submit(job)
	# Cancel before scheduler dispatches it
	var cancelled := _scheduler.cancel(jid)
	# Race: if already dispatched, fall back to cooperative cancel — either is fine
	if job.status == Job.Status.PENDING or job.status == Job.Status.CANCELLED:
		assert_true(cancelled or job.status == Job.Status.CANCELLED)


func test_queue_depth_per_priority() -> void:
	# Submit several jobs of different priorities
	for i in range(3):
		_scheduler.submit(_SimpleJob.new(i))
	var depth := _scheduler.get_queue_depth()
	assert_true(depth.has(Job.Priority.NORMAL))
	# Sum across priorities should be <= submitted count (some may dispatch)
	var total := 0
	for p in depth.keys():
		total += depth[p]
	assert_lte(total, 3)


func test_dependency_blocks_dispatch_until_dep_completes() -> void:
	var dep_job := _SimpleJob.new(1)
	var dep_jid := _scheduler.submit(dep_job)
	var dependent_job := _SimpleJob.new(2)
	dependent_job.dependencies = [dep_jid]
	var dependent_jid := _scheduler.submit(dependent_job)
	# Both should complete eventually; dependent only after dep
	await _scheduler.await_completion(dependent_jid)
	assert_eq(dep_job.status, Job.Status.COMPLETED)
	assert_eq(dependent_job.status, Job.Status.COMPLETED)
	# Dependent started after dep completed
	assert_gte(dependent_job.started_at_ms, dep_job.completed_at_ms)


func test_is_shutting_down_default_false() -> void:
	assert_false(_scheduler.is_shutting_down())
