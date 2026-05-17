## Phase 4.5 calibration harness — measures terrain renderer per-frame
## cost on real hardware.
##
## What this records (per ring_count + grid_n combo):
##   - avg main-thread frame time (ms) during a figure-8 camera walk
##   - peak main-thread frame time (ms)
##   - terrain page cache resident bytes
##   - resident page count
##
## GPU-side per-frame time is NOT measured here — Godot 4 dropped the
## Performance.RENDER_GPU_FRAME_TIME monitor; getting it back requires
## RenderingDevice.get_captured_timestamps_frame() which is a separate
## refactor. The CPU number measured here IS the hot path
## (TerrainWorld._process + JobScheduler tick + ResidencyManager diff
## + GpuJob render-thread serialization observed-from-main).
##
## Output: JSON to user://_calibration/terrain_<timestamp>.json
## Hand-imported into docs/build-notes/ + quality_tiers.json by the
## human after the run.
##
## NOT a regression test in the strict sense — it asserts very loose
## bounds (catastrophic-only). The PRIMARY product is the JSON record.
## Real RTX 3060 measurement requires running this on a 3060.

extends GutTest


const OUT_DIR := "user://_calibration"

# Tier configs to measure. ring_vertex_grid stays modest (64) so
# tests run in <1 minute each. Full production at 256 grid is
# extrapolated from these + the per-vert cost model.
const _CONFIGS := [
	{"name": "low_4r_64g",      "rings": 4, "grid": 64},
	{"name": "medium_5r_64g",   "rings": 5, "grid": 64},
	{"name": "high_6r_64g",     "rings": 6, "grid": 64},
	{"name": "ultra_7r_64g",    "rings": 7, "grid": 64},
	{"name": "cinematic_8r_64g","rings": 8, "grid": 64},
]


var _budget: StreamingBudget
var _scheduler: JobScheduler
var _tracker: GpuResourceTracker
var _camera: Node3D
var _tw: TerrainWorld
var _results: Array = []


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUT_DIR))


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
	_camera = Node3D.new()
	_camera.name = "Camera"
	get_tree().root.add_child(_camera)


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


func after_all() -> void:
	# Persist JSON summary
	var payload := {
		"phase": "4.5",
		"timestamp": Time.get_datetime_string_from_system(),
		"godot_version": Engine.get_version_info(),
		"results": _results,
	}
	var path: String = "%s/terrain_%d.json" % [
		OUT_DIR, Time.get_unix_time_from_system()]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
		gut.p("calibration record: %s" % path)


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless)")
		return true
	return false


# Walk camera in a figure-8 over the world, sampling per-frame
# main-thread time + GPU frame time. Returns a record dict.
func _measure_config(cfg: Dictionary, n_frames: int = 60) -> Dictionary:
	_tw = TerrainWorld.new()
	_tw.name = "TerrainWorld"
	_tw.ring_count = cfg["rings"]
	_tw.ring_vertex_grid = cfg["grid"]
	_tw.inner_cell_size_m = 0.5
	_tw.page_extent_m = 32.0
	_tw.terrain_pages_max = 128
	_tw.camera_path = NodePath("../Camera")
	get_tree().root.add_child(_tw)

	# Warm up — let pages stream + materials bind
	for i in range(60):
		_camera.global_position = Vector3(0.0, 50.0, 0.0)
		await get_tree().process_frame
		if _tw.is_full_detail_ready():
			break

	# Measure: figure-8 walk
	var cpu_samples: PackedFloat32Array = PackedFloat32Array()
	for i in range(n_frames):
		var t: float = float(i) / float(n_frames) * TAU
		# Figure-8 of radius 30m
		_camera.global_position = Vector3(
			sin(t) * 30.0,
			50.0,
			sin(t * 2.0) * 15.0,
		)
		var t0: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var cpu_us: float = float(Time.get_ticks_usec() - t0)
		cpu_samples.append(cpu_us / 1000.0)  # ms

	# Aggregate
	var cpu_avg: float = 0.0
	var cpu_peak: float = 0.0
	for v in cpu_samples:
		cpu_avg += v
		cpu_peak = max(cpu_peak, v)
	cpu_avg /= float(cpu_samples.size())

	var resident_pages: int = _tw.get_resident_pages().size()
	var resident_mb: float = 0.0
	var bgt_usage: Dictionary = _budget.get_system_usage("terrain_cache")
	if bgt_usage.has("resident_texture_mb"):
		resident_mb = float(bgt_usage["resident_texture_mb"])

	var rec := {
		"config": cfg["name"],
		"rings": cfg["rings"],
		"grid": cfg["grid"],
		"frames": n_frames,
		"cpu_avg_ms": cpu_avg,
		"cpu_peak_ms": cpu_peak,
		"resident_pages": resident_pages,
		"resident_mb": resident_mb,
		"full_detail_ready": _tw.is_full_detail_ready(),
	}
	gut.p("=== %s ===" % cfg["name"])
	gut.p("  cpu  avg=%.3fms  peak=%.3fms" % [cpu_avg, cpu_peak])
	gut.p("  resident: %d pages, %.1f MB" % [resident_pages, resident_mb])
	_results.append(rec)
	return rec


# --- one test per tier so failures show which tier blew up ---

func test_calibrate_low() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_config(_CONFIGS[0])
	# Catastrophic-only ceiling
	assert_lt(rec["cpu_avg_ms"], 200.0,
		"low tier cpu_avg blew catastrophic ceiling")


func test_calibrate_medium() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_config(_CONFIGS[1])
	assert_lt(rec["cpu_avg_ms"], 200.0)


func test_calibrate_high() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_config(_CONFIGS[2])
	assert_lt(rec["cpu_avg_ms"], 200.0)


func test_calibrate_ultra() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_config(_CONFIGS[3])
	assert_lt(rec["cpu_avg_ms"], 200.0)


func test_calibrate_cinematic() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_config(_CONFIGS[4])
	assert_lt(rec["cpu_avg_ms"], 200.0)
