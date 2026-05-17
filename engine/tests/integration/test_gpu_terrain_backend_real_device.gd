## Real-GPU tests for GpuTerrainBackend.
##
## Runs only under `python -m world5.verify --full` (which launches
## godot with --display-driver windows --rendering-driver vulkan to
## get a usable RenderingDevice). Skipped in --headless mode.
##
## Per spec 08a: backend touches RenderingDevice; must be invoked
## within a render-thread context. For test purposes we call
## generate_page directly because gut runs on main thread + Godot
## tolerates direct RD calls there in non-headless mode. Production
## consumers go through TerrainBackendAdapter (which uses GpuJob).

extends GutTest


# One shared backend for all tests so the cached shader is freed once
# in after_all instead of leaking N shader RIDs per test (each
# GpuTerrainBackend.new() compiles+caches one shader; RefCounted
# predelete during gut cleanup happens after the RD is dismantled).
var _shared_backend: GpuTerrainBackend = null


func before_all() -> void:
	_shared_backend = GpuTerrainBackend.new()


func after_all() -> void:
	if _shared_backend != null:
		_shared_backend.shutdown()
		_shared_backend = null


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless)")
		return true
	return false


func _basic_request(grid_n: int = 64) -> TerrainPageRequest:
	return TerrainPageRequest.from_dict({
		"world_xz": Vector2(0.0, 0.0),
		"extent_m": 256.0,
		"grid_n": grid_n,
		"seed": 42,
		"tier": "high",
		"capabilities": ["height_cpu"],
		"kernel_config_hash": "test_v1",
	})


func test_height_cpu_populated_with_finite_values() -> void:
	if _skip_if_no_rd():
		return
	var backend: GpuTerrainBackend = _shared_backend
	var req: TerrainPageRequest = _basic_request(64)
	var res: TerrainPageResult = backend.generate_page(req)

	assert_not_null(res)
	assert_true(res.has_capability("height_cpu"),
		"height_cpu populated for a height_cpu request")
	assert_eq(res.height_cpu.size(), 64 * 64,
		"height array size matches grid_n * grid_n")

	# All values finite + within amplitude bound
	for i in range(res.height_cpu.size()):
		var h: float = res.height_cpu[i]
		assert_true(is_finite(h), "h[%d] finite" % i)
		assert_lt(abs(h), 1000.0, "h[%d] within reasonable bound" % i)


func test_deterministic_for_same_seed() -> void:
	if _skip_if_no_rd():
		return
	var backend: GpuTerrainBackend = _shared_backend
	var res1: TerrainPageResult = backend.generate_page(_basic_request(32))
	var res2: TerrainPageResult = backend.generate_page(_basic_request(32))

	assert_eq(res1.height_cpu.size(), res2.height_cpu.size())
	for i in range(res1.height_cpu.size()):
		assert_eq(res1.height_cpu[i], res2.height_cpu[i],
			"same seed → same heights at index %d" % i)


func test_different_seed_produces_different_output() -> void:
	if _skip_if_no_rd():
		return
	var backend: GpuTerrainBackend = _shared_backend
	var req_a: TerrainPageRequest = _basic_request(32)
	var req_b: TerrainPageRequest = _basic_request(32)
	req_b.seed = 100

	var res_a: TerrainPageResult = backend.generate_page(req_a)
	var res_b: TerrainPageResult = backend.generate_page(req_b)

	var n_diff: int = 0
	for i in range(res_a.height_cpu.size()):
		if abs(res_a.height_cpu[i] - res_b.height_cpu[i]) > 1e-3:
			n_diff += 1
	assert_gt(n_diff, res_a.height_cpu.size() / 2,
		"different seeds produce different output for >50%% of samples")


func test_cache_key_populated() -> void:
	if _skip_if_no_rd():
		return
	var backend: GpuTerrainBackend = _shared_backend
	var req: TerrainPageRequest = _basic_request(32)
	var res: TerrainPageResult = backend.generate_page(req)
	assert_eq(res.cache_key, req.cache_key(),
		"result cache_key matches request cache_key")
	assert_eq(res.cache_key.length(), 64, "sha256 hex 64 chars")


func test_version_stamp_recorded() -> void:
	if _skip_if_no_rd():
		return
	var backend: GpuTerrainBackend = _shared_backend
	var res: TerrainPageResult = backend.generate_page(_basic_request(32))
	assert_eq(res.version_stamp.get("backend", ""), "gpu")
	assert_true(res.version_stamp.has("kernel_version"))
