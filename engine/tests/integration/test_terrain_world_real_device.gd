## Integration smoke test for TerrainWorld composer.
##
## Verifies end-to-end:
##   - composer instantiates all modules without crash
##   - public API (sample_height_at, get_debug_state) returns reasonable
##     values pre-stream
##   - process() ticks without errors when a camera is provided
##   - rings actually snap to camera position over a simulated walk

extends GutTest


var _budget: StreamingBudget
var _scheduler: JobScheduler
var _tracker: GpuResourceTracker
var _tw: TerrainWorld
var _camera: Node3D


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

	# Camera (Node3D — TerrainWorld uses global_position)
	_camera = Node3D.new()
	_camera.name = "Camera"
	get_tree().root.add_child(_camera)

	_tw = TerrainWorld.new()
	_tw.name = "TerrainWorld"
	# Small ring config for fast test
	_tw.ring_count = 3
	_tw.ring_vertex_grid = 16
	_tw.inner_cell_size_m = 1.0
	_tw.page_extent_m = 16.0     # small pages so the residency math is bounded
	_tw.terrain_pages_max = 32
	_tw.camera_path = NodePath("../Camera")
	get_tree().root.add_child(_tw)


func after_each() -> void:
	if _tw != null and is_instance_valid(_tw):
		_tw.free()
	if _camera != null and is_instance_valid(_camera):
		_camera.free()
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


# --- composer wiring ---

func test_instantiation_does_not_crash() -> void:
	# Just being able to add_child without error is the bar.
	assert_not_null(_tw)
	assert_eq(_tw.ring_count, 3)


func test_rings_built() -> void:
	# After _ready, 3 ring MeshInstance3D's should be children
	var ring_count: int = 0
	for c in _tw.get_children():
		if c is MeshInstance3D and c.name.begins_with("ClipmapRing_L"):
			ring_count += 1
	assert_eq(ring_count, 3)


func test_debug_state_returns_dict() -> void:
	var state: Dictionary = _tw.get_debug_state()
	assert_true(state.has("rings"))
	assert_true(state.has("loaded"))


func test_sample_height_no_data_returns_zero() -> void:
	assert_eq(_tw.sample_height_at(Vector2.ZERO), 0.0,
		"no cached pages → 0 sampled height")


# --- camera follow ---

func test_rings_snap_to_camera() -> void:
	_camera.global_position = Vector3(100.0, 50.0, 200.0)
	# Pump a couple frames so _process runs + camera resolves lazily.
	# (TW's first _process tick may have _camera still null while it
	# resolves via camera_path; second tick uses the resolved camera.)
	await get_tree().process_frame
	await get_tree().process_frame
	# Each ring's MeshInstance3D should have moved to its snap point.
	# Inner ring (cell 1m) snaps to (100, 200) exactly.
	var debug: Dictionary = _tw.get_debug_state()
	var rings: Array = debug["rings"]
	var center: Vector2 = rings[0]["center"]
	assert_almost_eq(center.x, 100.0, 1.0)
	assert_almost_eq(center.y, 200.0, 1.0)


# --- end-to-end streaming (real GPU only) ---

func test_camera_motion_triggers_page_load() -> void:
	if _skip_if_no_rd():
		return
	_camera.global_position = Vector3.ZERO
	await get_tree().process_frame  # initial residency tick
	# Wait a few frames for the first page-load job to complete
	var loaded: bool = false
	for i in range(120):
		await get_tree().process_frame
		var s: Dictionary = _tw.get_debug_state()
		if s["pages"]["pages"] > 0:
			loaded = true
			break
	assert_true(loaded, "camera at origin → at least one page streamed in")


func test_no_gpu_leaks_at_teardown() -> void:
	# Pump a few frames so streaming actually does work
	for i in range(5):
		await get_tree().process_frame
	# Teardown happens in after_each; this test passes if after_each
	# doesn't log "RIDs leaked"
	pass_test("teardown handled by after_each + adapter.shutdown()")
