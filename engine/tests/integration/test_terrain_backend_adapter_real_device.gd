## Integration tests for TerrainBackendAdapter — the public facade.
##
## Per spec 20 + spec 08a: every backend call goes through a GpuJob
## submitted via JobScheduler. This test verifies request → job →
## result flow end-to-end, plus that publishes to StreamingBudget
## fire correctly.
##
## Tests use the real RenderingDevice path (real GPU test layer)
## because the compute shader is the actual integration surface.

extends GutTest


var _scheduler: JobScheduler
var _budget: StreamingBudget
var _tracker: GpuResourceTracker
# Shared adapter so the underlying GpuTerrainBackend's cached shader
# is freed once via after_all, not per-test (avoids leaked shader RIDs
# during gut cleanup; see TB-REV-C2).
var _shared_adapter: TerrainBackendAdapter = null


func before_all() -> void:
	_shared_adapter = TerrainBackendAdapter.new()


func after_all() -> void:
	if _shared_adapter != null:
		_shared_adapter.shutdown()
		_shared_adapter = null


func before_each() -> void:
	# Reset adapter's last-job tracker so dependencies don't reference
	# job ids from the now-destroyed previous scheduler instance.
	if _shared_adapter != null:
		_shared_adapter._last_job_id = -1
	# Spawn the autoloads we depend on so /root/X lookups resolve
	# (same pattern as test_tier0_wired.gd — plugin autoloads only fire
	# in editor; in test runs we re-create them).
	_budget = StreamingBudget.new()
	_budget.name = "StreamingBudget"
	get_tree().root.add_child(_budget)

	_scheduler = JobScheduler.new()
	_scheduler.name = "JobScheduler"
	get_tree().root.add_child(_scheduler)

	_tracker = GpuResourceTracker.new()
	_tracker.name = "GpuResourceTracker"
	get_tree().root.add_child(_tracker)


func after_each() -> void:
	# Use free() not queue_free() so the autoload-path slots
	# (/root/JobScheduler etc.) are actually empty before the next
	# before_each adds new ones (otherwise the new test's adapter
	# would call get_node("/root/JobScheduler") and find the stale
	# (queue_free'd but not yet freed) one).
	if _scheduler != null and is_instance_valid(_scheduler):
		_scheduler.free()
	if _budget != null and is_instance_valid(_budget):
		_budget.free()
	if _tracker != null and is_instance_valid(_tracker):
		_tracker.free()


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless)")
		return true
	return false


func test_adapter_constructible() -> void:
	# Fresh instance test (not the shared one); shutdown immediately
	# so its shader RID frees while RD is still alive.
	var adapter: TerrainBackendAdapter = TerrainBackendAdapter.new()
	assert_not_null(adapter)
	adapter.shutdown()


func test_request_page_returns_job_id() -> void:
	# Even without RD, submit should accept the request + return a job id.
	# The result will fail-with-error inside the job, but submit itself
	# must work; consumers poll for completion.
	var adapter: TerrainBackendAdapter = _shared_adapter
	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2.ZERO, "extent_m": 256.0, "grid_n": 32,
		"seed": 0, "tier": "high",
		"capabilities": ["height_cpu"],
	})
	var job_id: int = adapter.request_page(req)
	assert_gt(job_id, 0, "request_page returns a valid job id")


func test_request_page_runs_via_job_scheduler() -> void:
	if _skip_if_no_rd():
		return

	var adapter: TerrainBackendAdapter = _shared_adapter
	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2.ZERO, "extent_m": 256.0, "grid_n": 32,
		"seed": 7, "tier": "high",
		"capabilities": ["height_cpu"],
	})
	var job_id: int = adapter.request_page(req)

	# Use the scheduler's await_completion coroutine. Returns the
	# job's result (TerrainPageResult), or null on failure.
	var res_raw: Variant = await _scheduler.await_completion(job_id)
	assert_not_null(res_raw, "await_completion returned a result")
	var res: TerrainPageResult = res_raw as TerrainPageResult
	assert_not_null(res, "result is a TerrainPageResult")
	assert_true(res.has_capability("height_cpu"), "height_cpu populated")
	assert_eq(res.height_cpu.size(), 32 * 32, "result array size correct")


func test_request_page_publishes_to_streaming_budget() -> void:
	if _skip_if_no_rd():
		return
	var adapter: TerrainBackendAdapter = _shared_adapter
	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2.ZERO, "extent_m": 256.0, "grid_n": 32,
		"seed": 0, "tier": "high",
		"capabilities": ["height_cpu"],
	})
	var _job_id: int = adapter.request_page(req)
	await get_tree().process_frame

	# The JobScheduler publishes active_jobs to StreamingBudget on
	# its tick — so the wire we already test (test_tier0_wired.gd)
	# covers this. Just verify the publisher record exists.
	var publishers: Array = _budget.get_publishers()
	assert_true(publishers.has("job_scheduler"),
		"job_scheduler publishes to StreamingBudget when terrain requests run")
