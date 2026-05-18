## Stationary-camera baseline measurement (Phase 4.5 audit deferral).
##
## Phase 4.5's calibration harness measured continuous-motion cost,
## which bundled streaming-under-motion with pure render cost. The
## audit-deferred follow-up isolates pure render cost: park the
## camera, wait for full_detail_ready, then measure N frames with
## ZERO camera motion. The result is the "is clipmap rasterization
## itself in budget?" answer the F2 trigger needs.
##
## If stationary cost << motion cost, the bottleneck is streaming,
## not rendering, and the streaming-throughput fix unblocks the budget.
## If stationary cost ≈ motion cost, the renderer itself is over
## budget and ring_count needs to come down or visual ceiling drops.
##
## 2026-05-17 page_extent fix: pre-5.6, this harness used
## page_extent=32m. The Phase 5.6 cache auto-raise scales budget
## with visible page count; at page_extent=32m outer rings need
## thousands of pages → per-frame ring iteration dominates even at
## rest. Now uses production page_extent_m=256 so the working set
## reflects real workload. Per-tier ceilings match the calibration
## harness's spec 13 §Calibration HW + extrapolation pattern —
## 5090-measured ceilings; per-tier-target-HW perf-budget regression
## tests live separately.
##
## Real-GPU only; skipped headless.

extends GutTest


const OUT_DIR := "user://_calibration"

# Per-tier 5090-measured catastrophic-only ceilings. Stationary cost
# at rest should be MUCH lower than motion cost — pure render
# only, no streaming churn. These ceilings catch infinite-loop /
# per-frame-allocation / unbounded-iteration bugs.
const _CONFIGS := [
	{"name": "low_4r_stationary",    "rings": 4, "grid": 64, "tier": "low",    "ceiling_ms_5090": 25.0},
	{"name": "medium_5r_stationary", "rings": 5, "grid": 64, "tier": "medium", "ceiling_ms_5090": 25.0},
	{"name": "high_6r_stationary",   "rings": 6, "grid": 64, "tier": "high",   "ceiling_ms_5090": 40.0},
	{"name": "ultra_7r_stationary",  "rings": 7, "grid": 64, "tier": "ultra",  "ceiling_ms_5090": 60.0},
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
	var payload := {
		"phase": "4.6",
		"sub": "stationary_baseline",
		"timestamp": Time.get_datetime_string_from_system(),
		"godot_version": Engine.get_version_info(),
		"results": _results,
	}
	var path: String = "%s/stationary_%d.json" % [
		OUT_DIR, Time.get_unix_time_from_system()]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
		gut.p("stationary baseline record: %s" % path)


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless)")
		return true
	return false


func _measure_stationary(cfg: Dictionary,
		n_frames: int = 60) -> Dictionary:
	_tw = TerrainWorld.new()
	_tw.name = "TerrainWorld"
	_tw.ring_count = cfg["rings"]
	_tw.ring_vertex_grid = cfg["grid"]
	_tw.inner_cell_size_m = 0.5
	# Use production page_extent (256m). Pre-2026-05-17 was 32m
	# which combined with Phase 5.6 cache auto-raise made outer
	# rings need thousands of pages and dominated per-frame cost
	# even at rest. See calibration test for the same fix.
	_tw.page_extent_m = 256.0
	_tw.terrain_pages_max = 128
	_tw.camera_path = NodePath("../Camera")
	get_tree().root.add_child(_tw)

	# Park camera + wait for full_detail_ready (drains streaming).
	_camera.global_position = Vector3.ZERO
	var settle: int = 0
	for i in range(240):
		await get_tree().process_frame
		settle = i
		if _tw.is_full_detail_ready():
			break

	# Measure N stationary frames (camera does NOT move)
	var cpu_samples: PackedFloat32Array = PackedFloat32Array()
	for i in range(n_frames):
		var t0: int = Time.get_ticks_usec()
		await get_tree().process_frame
		var cpu_us: float = float(Time.get_ticks_usec() - t0)
		cpu_samples.append(cpu_us / 1000.0)

	var cpu_avg: float = 0.0
	var cpu_peak: float = 0.0
	for v in cpu_samples:
		cpu_avg += v
		cpu_peak = max(cpu_peak, v)
	cpu_avg /= float(cpu_samples.size())

	var rec := {
		"config": cfg["name"],
		"rings": cfg["rings"],
		"grid": cfg["grid"],
		"settle_frames": settle,
		"settled": _tw.is_full_detail_ready(),
		"measure_frames": n_frames,
		"cpu_avg_ms": cpu_avg,
		"cpu_peak_ms": cpu_peak,
	}
	gut.p("=== %s ===" % cfg["name"])
	gut.p("  settle: %d frames, settled=%s" % [settle, _tw.is_full_detail_ready()])
	gut.p("  stationary: cpu avg=%.3fms peak=%.3fms" % [cpu_avg, cpu_peak])
	_results.append(rec)
	return rec


# --- per-tier stationary measurements ---


func _assert_catastrophic_ceiling(cfg: Dictionary, rec: Dictionary) -> void:
	var ceiling: float = float(cfg.get("ceiling_ms_5090", 50.0))
	var measured: float = float(rec["cpu_avg_ms"])
	assert_lt(measured, ceiling,
		"stationary %s cpu_avg %.2fms blew catastrophic ceiling %.2fms (5090-measured)" % [
			cfg["tier"], measured, ceiling])


func test_stationary_low() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_stationary(_CONFIGS[0])
	_assert_catastrophic_ceiling(_CONFIGS[0], rec)


func test_stationary_medium() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_stationary(_CONFIGS[1])
	_assert_catastrophic_ceiling(_CONFIGS[1], rec)


func test_stationary_high() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_stationary(_CONFIGS[2])
	_assert_catastrophic_ceiling(_CONFIGS[2], rec)


func test_stationary_ultra() -> void:
	if _skip_if_no_rd():
		return
	var rec: Dictionary = await _measure_stationary(_CONFIGS[3])
	_assert_catastrophic_ceiling(_CONFIGS[3], rec)
