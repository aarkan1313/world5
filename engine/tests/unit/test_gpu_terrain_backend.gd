## Tests for GpuTerrainBackend — request → result via compute shader.
##
## Headless-mode tests (this file): API shape, validation routing,
## error handling. The actual compute dispatch + GPU readback lives
## in tests/integration/test_gpu_terrain_backend_real_device.gd
## (needs --display-driver windows --rendering-driver vulkan).

extends GutTest


func test_backend_constructible() -> void:
	var backend: GpuTerrainBackend = GpuTerrainBackend.new()
	assert_not_null(backend)
	assert_eq(backend.name(), "gpu")


func test_invalid_request_returns_error_result() -> void:
	# Empty capabilities should be rejected before any GPU work
	var backend: GpuTerrainBackend = GpuTerrainBackend.new()
	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2.ZERO, "extent_m": 256.0, "grid_n": 256,
		"seed": 0, "tier": "high",
		"capabilities": [],  # invalid: no-op request
	})
	var res: TerrainPageResult = backend.generate_page(req)
	assert_not_null(res)
	assert_false(res.is_complete())
	assert_true(res.version_stamp.has("error"),
		"validation failure recorded in version_stamp.error")


func test_unsupported_capability_rejected() -> void:
	# Even with valid vocabulary, the GPU backend v1 doesn't yet
	# support every capability. Should record which ones it skipped.
	var backend: GpuTerrainBackend = GpuTerrainBackend.new()
	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2.ZERO, "extent_m": 256.0, "grid_n": 256,
		"seed": 0, "tier": "high",
		"capabilities": ["height_cpu", "drainage_map"],
		# drainage_map requires ErosionKernel, not in Phase 4.2 scope
	})
	var res: TerrainPageResult = backend.generate_page(req)
	# drainage_map should not be populated, but the call doesn't crash
	assert_false(res.has_capability("drainage_map"))


# --- Real-GPU compute path is exercised in:
#     tests/integration/test_gpu_terrain_backend_real_device.gd
#   This file stays headless-safe; do not call into RenderingDevice here.
