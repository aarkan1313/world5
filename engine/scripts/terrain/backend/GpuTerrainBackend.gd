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
const EROSION_SHADER_PATH := "res://addons/world5/shaders/terrain_erosion.glsl"
const EROSION_THERMAL_SHADER_PATH := "res://addons/world5/shaders/terrain_erosion_thermal.glsl"


# Cached shader source text (loaded once)
var _shader_source: String = ""
var _erosion_shader_source: String = ""
var _erosion_thermal_shader_source: String = ""
# Cached compiled shader RID for the backend's owned local RD.
var _shader_rid: RID = RID()
var _erosion_shader_rid: RID = RID()
var _erosion_thermal_shader_rid: RID = RID()
# Local RenderingDevice — created on first use; owned by the backend
# (per Phase 4.8 fix). Lifetime: backend's lifetime; freed in
# shutdown(). DO NOT share across backend instances since each owns
# its RIDs.
var _rd: RenderingDevice = null
# DEM source registry. Bundle loader (TerrainWorld) registers each
# DemSource by ID; chain dispatch looks up by DemFeatureKernel.source.
# Cleared in shutdown(). Sprint 3 bake-route: DemSource holds pre-
# baked feature grids; we CPU-blend the appropriate feature into the
# height after the chain completes. Sprint 4 may swap for GPU samplers.
var _dem_sources: Dictionary = {}  # source_id: String -> DemSource

# Residency-byte publishing moved to PageStreamingJob (TR-INTEG-C2 fix):
# the cache is the source of truth, not the backend.


func name() -> String:
	return "gpu"


## Register a DemSource by ID. TerrainWorld calls this at bundle load
## for each DEM declared in `<bundle>/dem/`. Idempotent — re-register
## with the same ID replaces the prior entry (lets a bundle reload
## refresh).
func register_dem_source(source_id: String, source: Object) -> void:
	if source_id == "" or source == null:
		return
	_dem_sources[source_id] = source


## Clear all registered DEM sources. Called by TerrainWorld._exit_tree
## as part of bundle teardown.
func clear_dem_sources() -> void:
	_dem_sources.clear()


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
		"chain_hash": (request.composer.chain_hash() if request.composer else ""),
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

	# Branch: chain path (composer set) vs legacy single-noise (kernel
	# field set or default). Composer wins when both are present
	# (matches TerrainPageRequest.cache_key precedence).
	var heights: PackedFloat32Array
	if request.composer != null and request.composer.stages.size() > 0:
		heights = _generate_chain(rd, request)
	else:
		heights = _generate_heights(rd, request)
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


## Chain-aware page generation. Runs the composer's stages in order:
## noise generator -> N erosion iterations (interleaved hydraulic +
## thermal) -> readback.
##
## Same return shape as `_generate_heights` for the consumer (a flat
## PackedFloat32Array of grid_n² height samples). Differs internally
## by maintaining persistent work buffers (water, sediment, velocity,
## drainage) across erosion iterations.
##
## Per spec 08a: runs on the render thread (caller guarantees via
## TerrainBackendAdapter -> GpuJob), so all RD ops are thread-safe.
func _generate_chain(rd: RenderingDevice,
		request: TerrainPageRequest) -> PackedFloat32Array:
	# Lazy compile of base + erosion shaders.
	if not _shader_rid.is_valid():
		if not _compile_shader(rd):
			return PackedFloat32Array()
	# Erosion shaders only compiled if the chain needs them.
	var needs_erosion: bool = request.composer.has_erosion()
	if needs_erosion:
		if not _erosion_shader_rid.is_valid():
			if not _compile_erosion_shader(rd):
				return PackedFloat32Array()
		if not _erosion_thermal_shader_rid.is_valid():
			if not _compile_erosion_thermal_shader(rd):
				return PackedFloat32Array()

	var n: int = request.grid_n
	var total_samples: int = n * n
	var bytes_height: int = total_samples * 4

	var tracker: Node = W5Lookup.find("GpuResourceTracker")
	var buffers: Array = []  # RIDs to free on exit

	# height buffer A — base generator writes here, hydraulic mutates
	# in place, thermal ping-pongs to/from height_b.
	var height_a: RID = rd.storage_buffer_create(bytes_height)
	if not height_a.is_valid():
		return PackedFloat32Array()
	buffers.append(height_a)
	if tracker != null:
		tracker.register(height_a, "terrain_backend", "buffer:height_a", bytes_height)

	# Stage 1: noise generator into height_a.
	var base_kernel: NoiseStackKernel = request.composer.base_noise_kernel()
	if base_kernel == null:
		_free_chain_buffers(rd, buffers, tracker)
		Log.error("terrain_backend", "chain has no base generator", {})
		return PackedFloat32Array()
	if not _dispatch_noise(rd, height_a, request, base_kernel):
		_free_chain_buffers(rd, buffers, tracker)
		return PackedFloat32Array()

	# If no erosion in the chain, read back height_a directly.
	if not needs_erosion:
		var raw_only: PackedByteArray = rd.buffer_get_data(height_a)
		_free_chain_buffers(rd, buffers, tracker)
		var heights_no_erosion: PackedFloat32Array = raw_only.to_float32_array()
		# DEM feature stages still apply even without erosion.
		for dk in request.composer.dem_feature_stages():
			_apply_dem_feature_blend(heights_no_erosion, request, dk, base_kernel)
		return heights_no_erosion

	# Allocate erosion work buffers (water, sediment, velocity, drainage,
	# height_b for thermal ping-pong). All initialized to zero by Godot.
	var bytes_vel: int = total_samples * 4 * 2  # 2 floats per cell
	var water: RID = rd.storage_buffer_create(bytes_height)
	var sediment: RID = rd.storage_buffer_create(bytes_height)
	var velocity: RID = rd.storage_buffer_create(bytes_vel)
	var drainage: RID = rd.storage_buffer_create(bytes_height)
	var height_b: RID = rd.storage_buffer_create(bytes_height)
	if not (water.is_valid() and sediment.is_valid()
			and velocity.is_valid() and drainage.is_valid()
			and height_b.is_valid()):
		# Partial allocations get tracked + freed via the buffers list
		if water.is_valid(): buffers.append(water)
		if sediment.is_valid(): buffers.append(sediment)
		if velocity.is_valid(): buffers.append(velocity)
		if drainage.is_valid(): buffers.append(drainage)
		if height_b.is_valid(): buffers.append(height_b)
		_free_chain_buffers(rd, buffers, tracker)
		return PackedFloat32Array()
	buffers.append(water)
	buffers.append(sediment)
	buffers.append(velocity)
	buffers.append(drainage)
	buffers.append(height_b)
	if tracker != null:
		tracker.register(water, "terrain_backend", "buffer:water", bytes_height)
		tracker.register(sediment, "terrain_backend", "buffer:sediment", bytes_height)
		tracker.register(velocity, "terrain_backend", "buffer:velocity", bytes_vel)
		tracker.register(drainage, "terrain_backend", "buffer:drainage", bytes_height)
		tracker.register(height_b, "terrain_backend", "buffer:height_b", bytes_height)

	# Stage 2+: each erosion stage in the chain. Multiple erosion stages
	# are allowed (e.g. coarse erosion followed by fine); they run with
	# their own iteration counts back-to-back over the same buffer set.
	# Each stage's intermediate state (water, sediment) IS carried over
	# (matches the Python reference's behavior when chaining bake_page
	# calls — water doesn't reset between stages).
	var height_current: RID = height_a
	var height_other: RID = height_b
	for ek in request.composer.erosion_stages():
		var swap_result: Array = _dispatch_erosion(
			rd, height_current, height_other, water, sediment,
			velocity, drainage, ek, n)
		if swap_result.is_empty():
			_free_chain_buffers(rd, buffers, tracker)
			return PackedFloat32Array()
		height_current = swap_result[0]
		height_other = swap_result[1]

	# Final readback from whichever height buffer holds the latest result.
	var raw: PackedByteArray = rd.buffer_get_data(height_current)
	var heights_out: PackedFloat32Array = raw.to_float32_array()

	_free_chain_buffers(rd, buffers, tracker)

	# Sprint 3 bake-route: apply DEM feature blends on CPU as a final
	# post-process. Each dem_feature stage samples the pre-baked feature
	# grid at every page cell and blends into the height per its
	# `strength` param. v1 uses ridge_emphasis as a positive bias scaled
	# by the noise stage's amplitude (so DEM ridges visibly emerge from
	# noise without overpowering); other modes blend additively scaled
	# by amplitude * 0.5. Sprint 4 may move this to GPU compute + apply
	# DEM blends BEFORE erosion (correct ordering vs the v1 post-only).
	for dk in request.composer.dem_feature_stages():
		_apply_dem_feature_blend(heights_out, request, dk, base_kernel)

	return heights_out


func _apply_dem_feature_blend(heights: PackedFloat32Array,
		request: TerrainPageRequest,
		kernel: DemFeatureKernel,
		base_kernel: NoiseStackKernel) -> void:
	# Look up the source. Missing source = noop + log (the world
	# contract validator should have caught this at bundle load).
	if not _dem_sources.has(kernel.source):
		Log.warn("terrain_backend", "dem_feature source not registered",
			{"source": kernel.source, "mode": kernel.mode})
		return
	var src: Object = _dem_sources[kernel.source]
	if not src.call("has_feature", kernel.mode):
		Log.warn("terrain_backend", "dem_feature missing baked feature",
			{"source": kernel.source, "mode": kernel.mode})
		return
	var n: int = request.grid_n
	var cell: float = request.extent_m / max(float(n - 1), 1.0)
	var origin_x: float = request.world_xz.x
	var origin_z: float = request.world_xz.y
	# Scale: bind the DEM feature's contribution to the noise stage's
	# amplitude so it stays proportional to the height stream's range.
	var amp: float = base_kernel.amplitude if base_kernel != null else 50.0
	var strength: float = clamp(kernel.strength, 0.0, 1.0)
	# Mode-specific blend rules. ridge_emphasis is the v1 hero: it
	# adds positive bias proportional to (already-normalized) ridge
	# strength × amp × stage_strength. Other modes use a centered
	# (signed) blend to avoid uniformly raising the height field.
	var center: float = 0.5
	if kernel.mode == DemFeatureKernel.MODE_RIDGE_EMPHASIS:
		# Ridge mode: pure additive (already normalized [0,1]).
		for i in range(n):
			for j in range(n):
				var wx: float = origin_x + float(j) * cell
				var wz: float = origin_z + float(i) * cell
				var f: float = src.call("sample_feature_world_xz",
					kernel.mode, wx, wz)
				heights[i * n + j] += f * amp * strength
	else:
		# Other modes: centered around 0.5 so values < 0.5 shift down,
		# > 0.5 shift up. Multiplied by amp * 0.5 * strength.
		for i in range(n):
			for j in range(n):
				var wx: float = origin_x + float(j) * cell
				var wz: float = origin_z + float(i) * cell
				var f: float = src.call("sample_feature_world_xz",
					kernel.mode, wx, wz)
				heights[i * n + j] += (f - center) * amp * strength


func _free_chain_buffers(rd: RenderingDevice, buffers: Array,
		tracker: Node) -> void:
	for rid in buffers:
		if rid.is_valid():
			rd.free_rid(rid)
			if tracker != null:
				tracker.unregister(rid)


## Dispatch the noise generator into `out_buf`. Returns true on success.
## Extracted from `_generate_heights` so the chain path can reuse the
## same noise dispatch without redundant readback.
func _dispatch_noise(rd: RenderingDevice, out_buf: RID,
		request: TerrainPageRequest, kernel: NoiseStackKernel) -> bool:
	var n: int = request.grid_n
	# Uniform set: binding 0 = output buffer
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(out_buf)
	var uniform_set: RID = rd.uniform_set_create([uniform], _shader_rid, 0)
	if not uniform_set.is_valid():
		return false
	# Push constants — same layout as terrain_page_gen.glsl (48 bytes).
	var pc: PackedByteArray = PackedByteArray()
	pc.resize(48)
	pc.encode_float(0, request.world_xz.x)
	pc.encode_float(4, request.world_xz.y)
	pc.encode_float(8, request.extent_m)
	pc.encode_u32(12, n)
	pc.encode_u32(16, request.seed)
	pc.encode_u32(20, kernel.octaves)
	pc.encode_float(24, kernel.frequency)
	pc.encode_float(28, kernel.lacunarity)
	pc.encode_float(32, kernel.gain)
	pc.encode_float(36, kernel.amplitude)
	pc.encode_u32(40, 0)
	pc.encode_u32(44, 0)
	var pipeline: RID = rd.compute_pipeline_create(_shader_rid)
	if not pipeline.is_valid():
		rd.free_rid(uniform_set)
		return false
	var groups: int = (n + 7) / 8
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, pc, pc.size())
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)
	return true


## Dispatch one ErosionKernel stage: N hydraulic steps + interleaved
## thermal steps. height_in is the current height buffer; height_other
## is the ping-pong target for thermal. Returns [new_current, new_other]
## (swapped if any thermal steps ran), or empty Array on failure.
func _dispatch_erosion(rd: RenderingDevice,
		height_in: RID, height_other: RID,
		water: RID, sediment: RID, velocity: RID, drainage: RID,
		kernel: ErosionKernel, n: int) -> Array:
	# Pipelines created once per stage (reused per iteration).
	var hydraulic_pipeline: RID = rd.compute_pipeline_create(_erosion_shader_rid)
	var thermal_pipeline: RID = rd.compute_pipeline_create(_erosion_thermal_shader_rid)
	if not (hydraulic_pipeline.is_valid() and thermal_pipeline.is_valid()):
		if hydraulic_pipeline.is_valid(): rd.free_rid(hydraulic_pipeline)
		if thermal_pipeline.is_valid(): rd.free_rid(thermal_pipeline)
		return []

	# Thermal threshold derived from talus angle (cell_size assumed 1
	# in non-dimensional units, matching Python ref).
	var talus_height: float = tan(deg_to_rad(kernel.talus_angle_deg))

	# Thermal-every interleave matches Python ref logic.
	var thermal_every: int = 0
	if kernel.thermal_iterations > 0 and kernel.iterations > 0:
		thermal_every = max(1, kernel.iterations / max(kernel.thermal_iterations, 1))
	elif kernel.thermal_iterations > 0:
		thermal_every = 1  # only thermal mode

	var groups: int = (n + 7) / 8
	var current_height: RID = height_in
	var other_height: RID = height_other

	for it in range(kernel.iterations):
		if not _dispatch_hydraulic_step(rd, hydraulic_pipeline,
				current_height, water, sediment, velocity, drainage,
				kernel, n, groups):
			rd.free_rid(hydraulic_pipeline)
			rd.free_rid(thermal_pipeline)
			return []
		# Interleave thermal per the same cadence as Python.
		if kernel.thermal_iterations > 0 and thermal_every > 0 \
				and (it % thermal_every == 0):
			if not _dispatch_thermal_step(rd, thermal_pipeline,
					current_height, other_height,
					talus_height, kernel.talus_rate, n, groups):
				rd.free_rid(hydraulic_pipeline)
				rd.free_rid(thermal_pipeline)
				return []
			# Swap height buffers so the latest is always `current`.
			var tmp: RID = current_height
			current_height = other_height
			other_height = tmp

	# iterations == 0 case: only thermal_iterations of pure thermal.
	if kernel.iterations == 0 and kernel.thermal_iterations > 0:
		for _i in range(kernel.thermal_iterations):
			if not _dispatch_thermal_step(rd, thermal_pipeline,
					current_height, other_height,
					talus_height, kernel.talus_rate, n, groups):
				rd.free_rid(hydraulic_pipeline)
				rd.free_rid(thermal_pipeline)
				return []
			var tmp2: RID = current_height
			current_height = other_height
			other_height = tmp2

	rd.free_rid(hydraulic_pipeline)
	rd.free_rid(thermal_pipeline)
	return [current_height, other_height]


func _dispatch_hydraulic_step(rd: RenderingDevice, pipeline: RID,
		height: RID, water: RID, sediment: RID, velocity: RID, drainage: RID,
		kernel: ErosionKernel, n: int, groups: int) -> bool:
	# Uniform set bindings 0..4 = height/water/sediment/velocity/drainage
	# (matches terrain_erosion.glsl layout).
	var u_h: RDUniform = RDUniform.new()
	u_h.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_h.binding = 0; u_h.add_id(height)
	var u_w: RDUniform = RDUniform.new()
	u_w.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_w.binding = 1; u_w.add_id(water)
	var u_s: RDUniform = RDUniform.new()
	u_s.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_s.binding = 2; u_s.add_id(sediment)
	var u_v: RDUniform = RDUniform.new()
	u_v.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_v.binding = 3; u_v.add_id(velocity)
	var u_d: RDUniform = RDUniform.new()
	u_d.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_d.binding = 4; u_d.add_id(drainage)
	var uniform_set: RID = rd.uniform_set_create(
		[u_h, u_w, u_s, u_v, u_d], _erosion_shader_rid, 0)
	if not uniform_set.is_valid():
		return false
	# Push constants — matches terrain_erosion.glsl Params (32 bytes,
	# 16-byte aligned).
	var pc: PackedByteArray = PackedByteArray()
	pc.resize(32)
	pc.encode_u32(0, n)
	pc.encode_float(4, kernel.rain_rate)
	pc.encode_float(8, kernel.evaporation)
	pc.encode_float(12, kernel.sediment_capacity)
	pc.encode_float(16, kernel.dissolve_rate)
	pc.encode_float(20, kernel.deposit_rate)
	pc.encode_float(24, kernel.min_slope)
	pc.encode_float(28, 0.0)  # _pad0
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, pc, pc.size())
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(uniform_set)
	return true


func _dispatch_thermal_step(rd: RenderingDevice, pipeline: RID,
		height_in: RID, height_out: RID, talus_height: float,
		talus_rate: float, n: int, groups: int) -> bool:
	var u_in: RDUniform = RDUniform.new()
	u_in.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_in.binding = 0; u_in.add_id(height_in)
	var u_out: RDUniform = RDUniform.new()
	u_out.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_out.binding = 1; u_out.add_id(height_out)
	var uniform_set: RID = rd.uniform_set_create(
		[u_in, u_out], _erosion_thermal_shader_rid, 0)
	if not uniform_set.is_valid():
		return false
	# Push constants — matches terrain_erosion_thermal.glsl Params (16 bytes).
	var pc: PackedByteArray = PackedByteArray()
	pc.resize(16)
	pc.encode_u32(0, n)
	pc.encode_float(4, talus_height)
	pc.encode_float(8, talus_rate)
	pc.encode_float(12, 0.0)  # _pad0
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, pc, pc.size())
	rd.compute_list_dispatch(compute_list, groups, groups, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(uniform_set)
	return true


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


func _compile_erosion_shader(rd: RenderingDevice) -> bool:
	return _compile_named(rd, EROSION_SHADER_PATH, "erosion",
		func(src: String) -> void: _erosion_shader_source = src,
		func() -> String: return _erosion_shader_source,
		func(rid: RID) -> void: _erosion_shader_rid = rid,
		func() -> RID: return _erosion_shader_rid)


func _compile_erosion_thermal_shader(rd: RenderingDevice) -> bool:
	return _compile_named(rd, EROSION_THERMAL_SHADER_PATH, "erosion_thermal",
		func(src: String) -> void: _erosion_thermal_shader_source = src,
		func() -> String: return _erosion_thermal_shader_source,
		func(rid: RID) -> void: _erosion_thermal_shader_rid = rid,
		func() -> RID: return _erosion_thermal_shader_rid)


# Generic compile helper to avoid duplicating the _compile_shader body
# for each new GLSL we add. Closures supply the per-shader state slot.
func _compile_named(rd: RenderingDevice, path: String, label: String,
		set_src: Callable, get_src: Callable,
		set_rid: Callable, get_rid: Callable) -> bool:
	if String(get_src.call()) == "":
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			Log.error("terrain_backend", "cannot open shader",
				{"label": label, "path": path})
			return false
		set_src.call(f.get_as_text())
		f.close()
	var src: RDShaderSource = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = String(get_src.call())
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		Log.error("terrain_backend", "shader compile failed",
			{"label": label, "error": spirv.compile_error_compute})
		return false
	var rid: RID = rd.shader_create_from_spirv(spirv)
	if not rid.is_valid():
		Log.error("terrain_backend",
			"shader_create_from_spirv returned invalid RID",
			{"label": label})
		return false
	set_rid.call(rid)
	var tracker: Node = W5Lookup.find("GpuResourceTracker")
	if tracker != null:
		tracker.register(rid, "terrain_backend", "shader:" + label, 0)
	return true


## Explicit shutdown — frees the cached shader RID + unregisters from
## tracker + frees the local RD. Owner (TerrainBackendAdapter) MUST
## call this before letting the backend drop. Per spec 08a rule 5:
## owners free in _exit_tree before the tracker autoload unloads.
func shutdown() -> void:
	if _rd == null:
		return
	var tracker: Node = W5Lookup.find("GpuResourceTracker")
	for slot in [
		[_shader_rid, "_shader_rid"],
		[_erosion_shader_rid, "_erosion_shader_rid"],
		[_erosion_thermal_shader_rid, "_erosion_thermal_shader_rid"],
	]:
		var rid: RID = slot[0]
		if rid.is_valid():
			_rd.free_rid(rid)
			if tracker != null:
				tracker.unregister(rid)
	_shader_rid = RID()
	_erosion_shader_rid = RID()
	_erosion_thermal_shader_rid = RID()
	# DEM sources are RefCounted; clearing the registry drops our refs.
	_dem_sources.clear()
	# Local RD: free explicitly (Godot doesn't auto-cleanup since
	# create_local_rendering_device returns an unowned ref).
	_rd.free()
	_rd = null


func _notification(what: int) -> void:
	# Defensive fallback: if owner forgot to call shutdown(), try here.
	if what == NOTIFICATION_PREDELETE:
		if _rd != null:
			shutdown()
