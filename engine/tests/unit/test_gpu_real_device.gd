## Tests that actually exercise RenderingDevice in test mode.
##
## Per user request 2026-05-16: spec 08a's GpuJob + GpuResourceTracker
## should be testable against a REAL RenderingDevice, not just the
## class-shape stubs in test_gpu_cpu_contract.gd.
##
## Approach: invoke godot with --display-driver windows
## --rendering-driver vulkan (NOT --headless). This creates a real
## (possibly hidden) main RenderingDevice. RenderingServer.get_rendering_device()
## then returns a usable handle.
##
## These tests are tagged 'real_gpu' so they can be skipped in CI
## environments without a GPU. The verify CLI's gut layer skips this
## file by default and includes it via a separate verify mode.

extends GutTest


func test_rendering_device_available() -> void:
	# RenderingServer.get_rendering_device() is null in --headless;
	# it's available when launched with --display-driver windows.
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice not available (likely --headless mode); skipping real GPU tests. Run with --display-driver windows --rendering-driver vulkan to enable.")
		return
	assert_not_null(rd, "RenderingDevice available in non-headless mode")


func test_buffer_create_and_free() -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable; see test_rendering_device_available")
		return
	# Create a small storage buffer
	var data := PackedByteArray()
	data.resize(256)
	for i in range(256):
		data[i] = i % 256
	var buf := rd.storage_buffer_create(256, data)
	assert_true(buf.is_valid(), "storage buffer RID is valid")
	# Track via GpuResourceTracker
	var tracker := GpuResourceTracker.new()
	tracker.register(buf, "test_real_gpu", "buffer", 256)
	assert_eq(tracker.get_allocations().size(), 1)
	# Free
	rd.free_rid(buf)
	tracker.unregister(buf)
	assert_eq(tracker.get_allocations().size(), 0)
	tracker.free()


func test_compute_shader_dispatch() -> void:
	## Minimal compute shader test: vector double in place.
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable")
		return

	# Tiny GLSL compute shader: double every element in a storage buffer
	var shader_source := RDShaderSource.new()
	shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source.source_compute = """
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict buffer Data {
	float data[];
} buf;
void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i < buf.data.length()) {
		buf.data[i] = buf.data[i] * 2.0;
	}
}
"""
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	assert_eq(spirv.compile_error_compute, "", "compute shader compiled without error")

	var shader_rid := rd.shader_create_from_spirv(spirv)
	assert_true(shader_rid.is_valid())

	# Input data: 64 floats with values [0, 1, 2, ..., 63]
	var input_data := PackedFloat32Array()
	for i in range(64):
		input_data.append(float(i))
	var input_bytes := input_data.to_byte_array()

	var buffer_rid := rd.storage_buffer_create(input_bytes.size(), input_bytes)
	assert_true(buffer_rid.is_valid())

	# Bind buffer to set 0 binding 0
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer_rid)
	var uniform_set := rd.uniform_set_create([uniform], shader_rid, 0)
	assert_true(uniform_set.is_valid())

	# Create + run compute pipeline
	var pipeline := rd.compute_pipeline_create(shader_rid)
	assert_true(pipeline.is_valid())

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)  # 1 workgroup of 64 threads
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	# Read back
	var output_bytes := rd.buffer_get_data(buffer_rid)
	var output_data := output_bytes.to_float32_array()

	# Verify every value doubled
	for i in range(64):
		assert_almost_eq(output_data[i], float(i) * 2.0, 1e-5,
			"index %d doubled correctly" % i)

	# Cleanup
	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)
	rd.free_rid(buffer_rid)
	rd.free_rid(shader_rid)
