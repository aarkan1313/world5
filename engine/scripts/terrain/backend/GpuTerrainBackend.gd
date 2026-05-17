## GpuTerrainBackend — generates TerrainPageResult via compute shader.
##
## Per spec 20 + spec 08a. Reads the kernel config from the request +
## dispatches `engine/shaders/terrain_page_gen.glsl` on the
## RenderingDevice. Reads back to PackedFloat32Array for `height_cpu`
## capability; future work creates Texture2DRD for `height_gpu`.
##
## Thread-safety: this class assumes it's invoked on the render
## thread (via GpuJob). The TerrainBackendAdapter is the public API
## that wraps every call in a GpuJob.
##
## RenderingDevice: uses a LOCAL RD via
## RenderingServer.create_local_rendering_device() instead of the
## main RD. Godot 4.6 forbids explicit submit/sync on the main RD
## ("Only local devices can submit and sync"). The local RD path
## works in both standalone scenes + gut tests (Phase 4.8 fix from
## the 2026-05-17 visual-review session — the previous main-RD
## approach worked only by accident when gut's test viewport happened
## to provide a local RD; standalone runs were broken).
##
## Headless mode (no display server): create_local_rendering_device
## may still return null in some headless configurations;
## generate_page returns a result with version_stamp.error populated.
## No crash; lets unit tests run.

class_name GpuTerrainBackend extends RefCounted


const VERSION := "0.0.1"
const KERNEL_VERSION := "noise_stack_v1"
const SHADER_PATH := "res://addons/world5/shaders/terrain_page_gen.glsl"


# Cached shader source text (loaded once)
var _shader_source: String = ""
# Cached compiled shader RID for the backend's owned local RD.
var _shader_rid: RID = RID()
# Local RenderingDevice — created on first use; owned by the backend
# (per Phase 4.8 fix). Lifetime: backend's lifetime; freed in
# shutdown(). DO NOT share across backend instances since each owns
# its RIDs.
var _rd: RenderingDevice = null

# Residency-byte publishing moved to PageStreamingJob (TR-INTEG-C2 fix):
# the cache is the source of truth, not the backend.


func name() -> String:
	return "gpu"


## Main entry. Validates request, dispatches compute, packs result.
## Always returns a TerrainPageResult; failure cases set
## version_stamp.error.
func generate_page(request: TerrainPageRequest) -> TerrainPageResult:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = request
	res.cache_key = request.cache_key()
	res.version_stamp = {
		"backend": "gpu",
		"backend_version": VERSION,
		"kernel_version": KERNEL_VERSION,
		"kernel_config_hash": (request.kernel.config_hash() if request.kernel else ""),
	}

	# 1. Validate request
	var errors: Array = request.validate()
	if errors.size() > 0:
		res.version_stamp["error"] = "invalid_request: " + str(errors)
		return res
	# 1b. Validate kernel config if supplied
	if request.kernel != null:
		var kerrs: Array = request.kernel.validate()
		if kerrs.size() > 0:
			res.version_stamp["error"] = "invalid_kernel: " + str(kerrs)
			return res

	# 2. Get the backend's local RD (lazy-create on first call).
	#    Phase 4.8: was RenderingServer.get_rendering_device() (main
	#    RD); Godot 4.6 rejects explicit submit/sync on main RD.
	var rd: RenderingDevice = _ensure_rd()
	if rd == null:
		res.version_stamp["error"] = "no_rendering_device"
		return res

	# 3. Compute height for height_cpu / height_gpu capabilities
	#    Phase 4.2 v1: height only (no slope/biome/etc.) — other
	#    capabilities just don't get populated (has_capability returns
	#    false; is_complete returns false; consumer can detect).
	var wants_height_cpu: bool = request.capabilities.has("height_cpu")
	var wants_height_gpu: bool = request.capabilities.has("height_gpu")
	if not (wants_height_cpu or wants_height_gpu):
		# No work to do; valid no-op
		return res

	var heights: PackedFloat32Array = _generate_heights(rd, request)
	if heights.is_empty():
		res.version_stamp["error"] = "compute_dispatch_failed"
		return res

	if wants_height_cpu:
		res.height_cpu = heights
	# TR-INTEG-C2 fix: backend no longer publishes a monotonic high-
	# water mark. The cache is the source of truth for resident bytes,
	# and PageStreamingJob publishes after every cache change. Backend
	# generates pages but doesn't own residency.
	# height_gpu: TODO Phase 4.5 — wrap heights into a Texture2DRD
	# tracked via GpuResourceTracker (per spec 08a rule 3 + 5). When
	# this lands, gpu_pages publishing wires the same way.

	return res


# --- internal ---

# Lazy-create a local RD on first use. Returns null in environments
# where create_local_rendering_device fails (rare; e.g. some headless
# setups). Cached for the backend's lifetime.
func _ensure_rd() -> RenderingDevice:
	if _rd != null:
		return _rd
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		return null
	return _rd


func _generate_heights(rd: RenderingDevice,
		request: TerrainPageRequest) -> PackedFloat32Array:
	# Lazy shader compile (one-time per backend instance)
	if not _shader_rid.is_valid():
		if not _compile_shader(rd):
			return PackedFloat32Array()

	# Kernel config: request-supplied or default. Per spec 19 + TB-REV-S3.
	var kernel: NoiseStackKernel = request.kernel
	if kernel == null:
		kernel = NoiseStackKernel.new()
	var octaves: int = kernel.octaves
	var frequency: float = kernel.frequency
	var lacunarity: float = kernel.lacunarity
	var gain: float = kernel.gain
	var amplitude: float = kernel.amplitude

	var n: int = request.grid_n
	var total_samples: int = n * n
	var bytes_needed: int = total_samples * 4  # float32

	# Output storage buffer
	var out_buf: RID = rd.storage_buffer_create(bytes_needed)
	if not out_buf.is_valid():
		return PackedFloat32Array()
	# Track via GpuResourceTracker if autoload available
	var tracker: Node = W5Lookup.find("GpuResourceTracker")
	if tracker != null:
		tracker.register(out_buf, "terrain_backend", "buffer", bytes_needed)

	# Uniform set: binding 0 = output buffer
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(out_buf)
	var uniform_set: RID = rd.uniform_set_create([uniform], _shader_rid, 0)
	if not uniform_set.is_valid():
		rd.free_rid(out_buf)
		if tracker != null: tracker.unregister(out_buf)
		return PackedFloat32Array()

	# Push constants: must match GLSL layout exactly + 16-byte align
	# Layout (matches Params block in terrain_page_gen.glsl):
	#   vec2  world_origin   (8 bytes, offset 0)
	#   float extent_m       (4 bytes, offset 8)
	#   uint  grid_n         (4 bytes, offset 12)
	#   uint  seed           (4 bytes, offset 16)
	#   uint  octaves        (4 bytes, offset 20)
	#   float frequency      (4 bytes, offset 24)
	#   float lacunarity     (4 bytes, offset 28)
	#   float gain           (4 bytes, offset 32)
	#   float amplitude      (4 bytes, offset 36)
	#   uint  _pad0          (4 bytes, offset 40)
	#   uint  _pad1          (4 bytes, offset 44)
	# Total: 48 bytes (multiple of 16, push-constant limit is 128)
	var pc: PackedByteArray = PackedByteArray()
	pc.resize(48)
	pc.encode_float(0, request.world_xz.x)
	pc.encode_float(4, request.world_xz.y)
	pc.encode_float(8, request.extent_m)
	pc.encode_u32(12, n)
	pc.encode_u32(16, request.seed)
	pc.encode_u32(20, octaves)
	pc.encode_float(24, frequency)
	pc.encode_float(28, lacunarity)
	pc.encode_float(32, gain)
	pc.encode_float(36, amplitude)
	pc.encode_u32(40, 0)  # _pad0
	pc.encode_u32(44, 0)  # _pad1

	# Pipeline + dispatch
	var pipeline: RID = rd.compute_pipeline_create(_shader_rid)
	if not pipeline.is_valid():
		rd.free_rid(uniform_set)
		rd.free_rid(out_buf)
		if tracker != null: tracker.unregister(out_buf)
		return PackedFloat32Array()

	# 8×8 workgroups — ceil(n/8) in each dim
	var groups: int = (n + 7) / 8
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, pc, pc.size())
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	# Read back
	var raw: PackedByteArray = rd.buffer_get_data(out_buf)
	var heights: PackedFloat32Array = raw.to_float32_array()

	# Cleanup
	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)
	rd.free_rid(out_buf)
	if tracker != null: tracker.unregister(out_buf)

	return heights


func _compile_shader(rd: RenderingDevice) -> bool:
	if _shader_source == "":
		var f: FileAccess = FileAccess.open(SHADER_PATH, FileAccess.READ)
		if f == null:
			Log.error("terrain_backend", "cannot open shader",
				{"path": SHADER_PATH})
			return false
		_shader_source = f.get_as_text()
		f.close()

	var src: RDShaderSource = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = _shader_source
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		Log.error("terrain_backend", "shader compile failed",
			{"error": spirv.compile_error_compute})
		return false
	_shader_rid = rd.shader_create_from_spirv(spirv)
	if not _shader_rid.is_valid():
		Log.error("terrain_backend",
			"shader_create_from_spirv returned invalid RID", {})
		return false
	# Track the shader RID
	var tracker: Node = W5Lookup.find("GpuResourceTracker")
	if tracker != null:
		tracker.register(_shader_rid, "terrain_backend", "shader", 0)
	# Note: _rd was set by _ensure_rd before _compile_shader was called.
	return true


## Explicit shutdown — frees the cached shader RID + unregisters from
## tracker + frees the local RD. Owner (TerrainBackendAdapter) MUST
## call this before letting the backend drop. Per spec 08a rule 5:
## owners free in _exit_tree before the tracker autoload unloads.
func shutdown() -> void:
	if _rd == null:
		return
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
		var tracker: Node = W5Lookup.find("GpuResourceTracker")
		if tracker != null:
			tracker.unregister(_shader_rid)
		_shader_rid = RID()
	# Local RD: free explicitly (Godot doesn't auto-cleanup since
	# create_local_rendering_device returns an unowned ref).
	_rd.free()
	_rd = null


func _notification(what: int) -> void:
	# Defensive fallback: if owner forgot to call shutdown(), try here.
	if what == NOTIFICATION_PREDELETE:
		if _rd != null:
			shutdown()
