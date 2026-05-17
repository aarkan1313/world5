## Integration test: PageStreamingJob wires ResidencyManager to
## TerrainBackendAdapter end-to-end.
##
## Flow: ResidencyManager.update(required) → emits page_load_requested
## → PageStreamingJob captures + submits to TerrainBackendAdapter →
## awaits → writes back to TerrainPageCache.
##
## Real-device (needs RD); skipped in headless.

extends GutTest


var _scheduler: JobScheduler
var _budget: StreamingBudget
var _tracker: GpuResourceTracker
var _cache: TerrainPageCache
var _residency: ResidencyManager
var _streaming: PageStreamingJob
var _adapter: TerrainBackendAdapter


func before_each() -> void:
	_budget = StreamingBudget.new()
	_budget.name = "StreamingBudget"
	get_tree().root.add_child(_budget)

	_scheduler = JobScheduler.new()
	_scheduler.name = "JobScheduler"
	get_tree().root.add_child(_scheduler)

	_tracker = GpuResourceTracker.new()
	_tracker.name = "GpuResourceTracker"
	get_tree().root.add_child(_tracker)

	_cache = TerrainPageCache.new()
	_cache.set_budget(64)

	_residency = ResidencyManager.new()
	_residency.configure(_cache, 256.0)
	get_tree().root.add_child(_residency)

	_adapter = TerrainBackendAdapter.new()

	_streaming = PageStreamingJob.new()
	_streaming.configure(_adapter, _cache)
	get_tree().root.add_child(_streaming)
	_residency.page_load_requested.connect(_streaming.on_load_requested)
	_residency.page_evict_requested.connect(_streaming.on_evict_requested)


func after_each() -> void:
	if _adapter != null:
		_adapter.shutdown()
	if _streaming != null and is_instance_valid(_streaming):
		_streaming.free()
	if _residency != null and is_instance_valid(_residency):
		_residency.free()
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


# --- end-to-end: residency requirement → cached page ---

func test_required_page_ends_up_in_cache() -> void:
	if _skip_if_no_rd():
		return

	# Pretend the renderer needs one page at (0, 0) ring 0
	_residency.update([{"ring": 0, "xz": Vector2.ZERO}])
	assert_false(_cache.has(0, Vector2.ZERO), "not yet loaded synchronously")

	# Wait for the load job to complete
	var max_frames: int = 120
	var loaded: bool = false
	for i in range(max_frames):
		await get_tree().process_frame
		if _cache.has(0, Vector2.ZERO):
			loaded = true
			break
	assert_true(loaded, "page loaded into cache within %d frames" % max_frames)

	# Stored page has data
	var page: TerrainPageResult = _cache.get_page(0, Vector2.ZERO)
	assert_not_null(page)
	assert_true(page.has_capability("height_cpu"))


# --- evict flows through to cache ---

func test_dropped_page_evicted_from_cache() -> void:
	if _skip_if_no_rd():
		return

	# Load
	_residency.update([{"ring": 0, "xz": Vector2.ZERO}])
	for i in range(120):
		await get_tree().process_frame
		if _cache.has(0, Vector2.ZERO):
			break
	assert_true(_cache.has(0, Vector2.ZERO))

	# Drop requirement → ResidencyManager emits evict → streaming clears cache
	_residency.update([])
	await get_tree().process_frame  # signal processing
	assert_false(_cache.has(0, Vector2.ZERO), "evicted page no longer cached")
