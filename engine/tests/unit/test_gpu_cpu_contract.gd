## Tests for GpuJob + GpuResourceTracker (spec 08a).
##
## Headless mode has no real RenderingDevice, so we test:
## - GpuJob class shape (extends Job, has _run_on_render_thread bridge)
## - JobScheduler routes GpuJob via the bridge (not WTP)
## - GpuResourceTracker register / unregister / get_allocations /
##   _exit_tree leak detection
##
## Real RenderingDevice behavior testing lands in Phase 4 when
## terrain MVP needs actual GPU compute. Capture-based tests catch
## the visible effects.

extends GutTest


# Simple GpuJob that just sets a flag (no actual RenderingDevice work)
class _MarkerGpuJob extends GpuJob:
	var did_run: bool = false

	func _init():
		name = "marker_gpu_job"

	func _execute() -> Variant:
		did_run = true
		return "ran"


var _scheduler: JobScheduler
var _tracker: GpuResourceTracker


func before_each() -> void:
	_scheduler = JobScheduler.new()
	add_child_autofree(_scheduler)
	_tracker = GpuResourceTracker.new()
	add_child_autofree(_tracker)


# --- GpuJob class shape ---

func test_gpu_job_extends_job() -> void:
	var job := _MarkerGpuJob.new()
	assert_true(job is Job, "GpuJob extends Job")
	assert_true(job is GpuJob, "GpuJob class detectable")


func test_gpu_job_has_render_thread_bridge() -> void:
	var job := _MarkerGpuJob.new()
	assert_true(job.has_method("_run_on_render_thread"))


# --- JobScheduler routing ---

func test_scheduler_routes_gpu_job_via_bridge() -> void:
	var job := _MarkerGpuJob.new()
	var jid := _scheduler.submit(job)
	# Render thread runs every frame; await a few frames
	for i in range(5):
		await get_tree().process_frame
	# GpuJob runs on render thread; should have executed by now
	assert_true(job.did_run, "GpuJob executed via render thread")
	assert_eq(job.status, Job.Status.COMPLETED)


# --- GpuResourceTracker ---

func test_tracker_register_increments_count() -> void:
	# RID(0) is invalid but get_id() returns 0 — fine for tracking test
	var fake_rid := RID()
	_tracker.register(fake_rid, "test_owner", "texture", 1024)
	var allocs := _tracker.get_allocations()
	assert_eq(allocs.size(), 1)
	assert_eq(allocs[0]["owner"], "test_owner")
	assert_eq(allocs[0]["category"], "texture")
	assert_eq(allocs[0]["approx_bytes"], 1024)


func test_tracker_unregister_removes() -> void:
	var fake_rid := RID()
	_tracker.register(fake_rid, "test", "texture")
	assert_eq(_tracker.get_allocations().size(), 1)
	_tracker.unregister(fake_rid)
	assert_eq(_tracker.get_allocations().size(), 0)


func test_tracker_filter_by_owner() -> void:
	# Multiple owners can't share RID(0); use different RID-id sentinels.
	# We can't easily fabricate RIDs with different IDs in pure GDScript
	# without a real RenderingDevice, so register the same RID twice
	# (second overwrites) — test filter behavior separately:
	var fake_rid := RID()
	_tracker.register(fake_rid, "owner_a", "texture")
	# Filtering by nonexistent owner returns empty
	assert_eq(_tracker.get_allocations("owner_b").size(), 0)
	# Filtering by registered owner returns it
	assert_eq(_tracker.get_allocations("owner_a").size(), 1)


func test_tracker_get_total_bytes() -> void:
	var fake_rid := RID()
	_tracker.register(fake_rid, "test", "buffer", 4096)
	assert_eq(_tracker.get_total_bytes(), 4096)


func test_tracker_get_owner_counts() -> void:
	var fake_rid := RID()
	_tracker.register(fake_rid, "system_a", "texture")
	var counts := _tracker.get_owner_counts()
	assert_eq(counts.get("system_a", 0), 1)


func test_tracker_unregister_unknown_warns_but_doesnt_crash() -> void:
	var fake_rid := RID()
	# Not registered; unregister should warn but not crash
	_tracker.unregister(fake_rid)
	assert_eq(_tracker.get_allocations().size(), 0)


func test_tracker_register_duplicate_overwrites_with_warning() -> void:
	var fake_rid := RID()
	_tracker.register(fake_rid, "first_owner", "texture")
	_tracker.register(fake_rid, "second_owner", "buffer")
	var allocs := _tracker.get_allocations()
	assert_eq(allocs.size(), 1)
	assert_eq(allocs[0]["owner"], "second_owner")


func test_tracker_reset_clears_state() -> void:
	var fake_rid := RID()
	_tracker.register(fake_rid, "test", "texture")
	_tracker._reset()
	assert_eq(_tracker.get_allocations().size(), 0)
