## TerrainWorld — the composer for the clipmap terrain renderer.
##
## Per spec 21. This node is what consumers instance in their scenes
## (engine/scenes/components/terrain_world.tscn). It wires together:
##
##   geometry  ClipmapGeometry        cold-builds N ring meshes
##   ring      ClipmapRing × N        owns one MeshInstance3D each
##   dispatch  ClipmapDispatch        per-frame snap + morph compute
##   cache     TerrainPageCache       LRU page cache
##   residency ResidencyManager       diffs required vs cached
##   streaming PageStreamingJob       residency → backend → cache
##   material  MaterialPipeline       per-ring ShaderMaterial
##   macro     MacroAlbedo            world-spanning far-field albedo
##   slots     SurfaceSlotMask        surface-slot bindings
##   adapter   TerrainBackendAdapter  page generation facade
##   diag      RingDebugOverlay       toggleable debug visualization
##   probes    PageDebugProbes        introspection helpers
##
## Cap: ≤ 800 lines (spec 21 god-file prevention). Stays a thin
## composer — heavy lifting in the modules.

class_name TerrainWorld extends Node3D


# --- public exports ---
@export var world_bundle_path: String = ""           # "res://worlds/walking_demo/"
@export var camera_path: NodePath
@export var quality_tier_override: String = ""       # "" = QualityTiers current
@export var debug_overlay: bool = false
@export var ring_count: int = 6
@export var ring_vertex_grid: int = 256
@export var inner_cell_size_m: float = 0.5
@export var morph_band_fraction: float = 0.16
@export var page_extent_m: float = 256.0
@export var terrain_pages_max: int = 64


# --- signals ---
signal world_loaded()
signal world_unloaded()
signal full_detail_ready()
signal page_loaded(ring_index: int, page_xz: Vector2)
signal page_unloaded(ring_index: int, page_xz: Vector2)


# --- module instances ---
var _geometry: ClipmapGeometry = null
var _rings: Array = []                              # Array[ClipmapRing]
var _dispatch: ClipmapDispatch = null
var _cache: TerrainPageCache = null
var _residency: ResidencyManager = null
var _streaming: PageStreamingJob = null
var _material_pipeline: MaterialPipeline = null
var _macro: MacroAlbedo = null
var _slots: SurfaceSlotMask = null
var _adapter: TerrainBackendAdapter = null
var _diag: RingDebugOverlay = null
var _probes: PageDebugProbes = null
var _kernel: NoiseStackKernel = null

# Bookkeeping
var _camera: Node3D = null
var _loaded: bool = false
var _full_detail: bool = false
# Last camera-XZ a residency update saw (rounded to page boundary),
# used to skip the per-frame diff when the camera hasn't crossed a
# page edge (TR-SPEC-S6 + TR-PERF-S1 fix).
var _last_residency_camera_xz: Vector2 = Vector2(NAN, NAN)
# Page bookkeeping for full-detail readiness check + spec'd
# get_resident_pages() shape (TR-SPEC-C3 + TR-SPEC-S1).
# Key = "ring:x:z" → {ring, xz, age_ms}
var _page_load_times: Dictionary = {}


# --- lifecycle ---

func _ready() -> void:
	_build_modules()
	if world_bundle_path != "":
		_load_world_bundle(world_bundle_path)
	else:
		# No bundle = use shader defaults; still tick so smoke tests
		# + bare-bones demo scenes work. world_loaded fires only when
		# a real bundle landed.
		_loaded = true


func _process(_delta: float) -> void:
	if not _loaded:
		return
	# Resolve camera lazily (allows late binding)
	if _camera == null and not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Node3D
	if _camera == null:
		return

	var cam_pos: Vector3 = _camera.global_position
	var cam_xz: Vector2 = Vector2(cam_pos.x, cam_pos.z)

	# 1. Snap rings to camera (per-ring cell-aligned)
	_dispatch.update(_rings, cam_pos)

	# 2. Compute morph factor per ring + push to material
	for i in range(_rings.size()):
		var ring: ClipmapRing = _rings[i]
		var half_extent: float = float(ring_vertex_grid - 1) * ring.cell_size_m * 0.5
		var morph: float = _dispatch.compute_morph_factor(
			cam_xz, ring.snapped_center, half_extent, morph_band_fraction,
		)
		var mat: Material = ring.mesh_instance.material_override
		if mat is ShaderMaterial:
			_material_pipeline.set_morph_factor(mat as ShaderMaterial, morph)

	# 3. Residency update — dirty-check: only re-diff when camera crossed
	# a page boundary (TR-SPEC-S6 + TR-PERF-S1 fix). At rest with no
	# motion, this skips ~all the per-frame dict work.
	var cam_page_xz: Vector2 = Vector2(
		floor(cam_xz.x / page_extent_m),
		floor(cam_xz.y / page_extent_m),
	)
	if cam_page_xz != _last_residency_camera_xz:
		_last_residency_camera_xz = cam_page_xz
		var required: Array = []
		for i in range(_rings.size()):
			var ring: ClipmapRing = _rings[i]
			var ring_extent: float = float(ring_vertex_grid - 1) * ring.cell_size_m
			required.append_array(_residency.required_pages_for_ring(
				cam_xz, i, ring_extent))
		_residency.update(required)


# --- public API ---

func is_full_detail_ready() -> bool:
	return _full_detail


## Returns Array[Dictionary{"ring": int, "xz": Vector2, "age_ms": int}]
## per spec 21 §Public API (TR-SPEC-S1 fix).
func get_resident_pages() -> Array:
	if _cache == null:
		return []
	var now: int = Time.get_ticks_msec()
	var out: Array = []
	for k in _page_load_times.keys():
		var rec: Dictionary = _page_load_times[k]
		out.append({
			"ring": rec["ring"],
			"xz": rec["xz"],
			"age_ms": now - int(rec["loaded_at_ms"]),
		})
	return out


func sample_height_at(world_xz: Vector2) -> float:
	# Sample innermost ring's resident page if present; fallback 0.
	# Phase 4.4 stub — full per-cell sampling lands in Phase 4.6.
	if _cache == null:
		return 0.0
	var page_origin: Vector2 = Vector2(
		floor(world_xz.x / page_extent_m) * page_extent_m,
		floor(world_xz.y / page_extent_m) * page_extent_m,
	)
	var page: TerrainPageResult = _cache.get_page(0, page_origin)
	if page == null or page.height_cpu.is_empty():
		return 0.0
	# Bilinear sample inside the page
	var local_xz: Vector2 = world_xz - page_origin
	var grid: int = int(sqrt(page.height_cpu.size()))
	if grid < 2:
		return 0.0
	var cell: float = page_extent_m / float(grid - 1)
	var fx: float = clamp(local_xz.x / cell, 0.0, float(grid - 1))
	var fy: float = clamp(local_xz.y / cell, 0.0, float(grid - 1))
	var ix: int = int(fx)
	var iy: int = int(fy)
	var ix1: int = min(ix + 1, grid - 1)
	var iy1: int = min(iy + 1, grid - 1)
	var dx: float = fx - float(ix)
	var dy: float = fy - float(iy)
	var h00: float = page.height_cpu[iy * grid + ix]
	var h10: float = page.height_cpu[iy * grid + ix1]
	var h01: float = page.height_cpu[iy1 * grid + ix]
	var h11: float = page.height_cpu[iy1 * grid + ix1]
	var top: float = h00 + (h10 - h00) * dx
	var bot: float = h01 + (h11 - h01) * dx
	return top + (bot - top) * dy


func get_debug_state() -> Dictionary:
	var rings_state: Array = []
	for r in _rings:
		var ring: ClipmapRing = r
		rings_state.append({
			"level": ring.level,
			"cell_m": ring.cell_size_m,
			"center": ring.snapped_center,
		})
	var probe_summary: Dictionary = {}
	if _probes != null:
		probe_summary = _probes.summary()
	return {
		"rings": rings_state,
		"pages": probe_summary,
		"loaded": _loaded,
	}


# --- module construction ---

func _build_modules() -> void:
	_geometry = ClipmapGeometry.new()
	_dispatch = ClipmapDispatch.new()
	_cache = TerrainPageCache.new()
	_cache.set_budget(terrain_pages_max)
	_material_pipeline = MaterialPipeline.new()
	_macro = MacroAlbedo.new()
	_slots = SurfaceSlotMask.new()
	_adapter = TerrainBackendAdapter.new()
	_probes = PageDebugProbes.new()
	_probes.configure(_cache, page_extent_m)

	# ResidencyManager + PageStreamingJob are Nodes — children of self.
	# Order: create both, then configure residency with the streaming
	# back-ref so residency can suppress in-flight re-emits per
	# TR-INTEG-C3 fix. (Single configure call — M1 audit fix collapsed
	# the pre-/post-streaming double-configure.)
	_residency = ResidencyManager.new()
	_residency.name = "ResidencyManager"
	add_child(_residency)

	_streaming = PageStreamingJob.new()
	_streaming.name = "PageStreamingJob"
	# Streaming gets all per-page params from us (TR-INTEG-C1, TR-SPEC-S5).
	# Capabilities: height_cpu for sampling + future GPU upload pathway
	# (height_gpu wires here when MaterialPipeline.bind_height_map_rd
	# lands per spec 08a; today we bind CPU→ImageTexture per-load).
	_streaming.configure(_adapter, _cache, page_extent_m, ring_vertex_grid,
		0, "high", _kernel, ["height_cpu"])
	add_child(_streaming)

	# Now configure residency with the streaming back-ref.
	_residency.configure(_cache, page_extent_m, _streaming)

	# Wire residency → streaming for actual page work
	_residency.page_load_requested.connect(_streaming.on_load_requested)
	_residency.page_evict_requested.connect(_streaming.on_evict_requested)
	# Public-signal relays + heightmap binding fire on the ACTUAL load
	# event (TR-INTEG-C3, TR-SPEC-C3 fix — was firing on request).
	_streaming.page_actually_loaded.connect(_on_page_actually_loaded)
	_streaming.page_actually_evicted.connect(_on_page_actually_evicted)

	# Build rings + materials
	var meshes: Array = _geometry.build(ring_count, ring_vertex_grid,
		inner_cell_size_m)
	for i in range(meshes.size()):
		var ring: ClipmapRing = ClipmapRing.new()
		ring.configure(meshes[i], i, inner_cell_size_m * pow(2.0, i))
		var mat: ShaderMaterial = _material_pipeline.make_ring_material(
			i, ring_vertex_grid)
		ring.mesh_instance.material_override = mat
		add_child(ring.mesh_instance)
		_rings.append(ring)

	# Diagnostics overlay (off by default per @export var)
	_diag = RingDebugOverlay.new()
	_diag.name = "RingDebugOverlay"
	add_child(_diag)
	_diag.bind_rings(_rings)
	_diag.set_enabled(debug_overlay)


# --- world bundle loading ---

func _load_world_bundle(bundle_path: String) -> void:
	# Phase 4.4 ships a minimal loader: macro albedo + surface_slots +
	# noise_stack kernel if present. Phase 4.6 expands to biome_catalog
	# per spec 14. Missing files are logged warn (TR-SPEC-S2 fix —
	# was silently no-op).
	var macro_cfg: String = bundle_path + "macro_albedo.json"
	if FileAccess.file_exists(macro_cfg):
		if _macro.load_from_path(macro_cfg):
			for ring in _rings:
				var mat: Material = ring.mesh_instance.material_override
				if mat is ShaderMaterial:
					_material_pipeline.bind_macro_albedo(mat as ShaderMaterial, _macro)
		else:
			Log.warn("terrain_world", "macro_albedo.json failed to load",
				{"path": macro_cfg})
	else:
		Log.warn("terrain_world", "bundle missing macro_albedo.json",
			{"bundle": bundle_path})

	var slots_cfg: String = bundle_path + "surface_slots.json"
	if FileAccess.file_exists(slots_cfg):
		if not _slots.load_from_path(slots_cfg):
			Log.warn("terrain_world", "surface_slots.json failed to load",
				{"path": slots_cfg})

	# Kernel config (TR-SPEC-S5 fix — was hard-coded defaults)
	var kernel_cfg: String = bundle_path + "kernels/noise_stack.json"
	if FileAccess.file_exists(kernel_cfg):
		var f: FileAccess = FileAccess.open(kernel_cfg, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_kernel = NoiseStackKernel.from_dict(parsed)
				# Re-configure streaming with the loaded kernel
				if _streaming != null:
					_streaming.configure(_adapter, _cache, page_extent_m,
						ring_vertex_grid, 0, "high", _kernel, ["height_cpu"])

	_loaded = true
	world_loaded.emit()


func _exit_tree() -> void:
	# Per spec 08a rule 5: free GPU resources BEFORE the autoload
	# tracker tears down. Adapter holds the cached shader RID
	# (TR-INTEG-S1 fix — was only freeing adapter; now also clears
	# cache + disconnects signals to defend against late-arriving
	# coroutines from in-flight page jobs).
	if _streaming != null:
		if _residency != null:
			if _residency.page_load_requested.is_connected(
					_streaming.on_load_requested):
				_residency.page_load_requested.disconnect(
					_streaming.on_load_requested)
			if _residency.page_evict_requested.is_connected(
					_streaming.on_evict_requested):
				_residency.page_evict_requested.disconnect(
					_streaming.on_evict_requested)
	if _adapter != null:
		_adapter.shutdown()
	if _cache != null:
		_cache.clear()
	# Tell StreamingBudget terrain is gone
	var budget: Node = W5Lookup.find("StreamingBudget")
	if budget != null:
		budget.clear("terrain_cache")
	if _loaded:
		world_unloaded.emit()


# --- page load / evict handlers ---

func _on_page_actually_loaded(ring: int, page_xz: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	_page_load_times[_page_key(ring, page_xz)] = {
		"ring": ring, "xz": page_xz, "loaded_at_ms": now,
	}
	# Bind heightmap to the matching ring's material if the page covers
	# the ring's center (Phase 4.4 simplification: one page per ring at
	# the center; outer-ring extents > page extent will show stretched
	# texture at edges — calibration sprint 4.5 picks the right ratio).
	if ring >= 0 and ring < _rings.size():
		var r: ClipmapRing = _rings[ring]
		# Only bind if THIS page covers the ring's snapped center
		var center_page_origin: Vector2 = Vector2(
			floor(r.snapped_center.x / page_extent_m) * page_extent_m,
			floor(r.snapped_center.y / page_extent_m) * page_extent_m,
		)
		if center_page_origin == page_xz:
			var page: TerrainPageResult = _cache.get_page(ring, page_xz)
			if page != null and not page.height_cpu.is_empty():
				_bind_height_to_ring(r, page)

	page_loaded.emit(ring, page_xz)

	# Full-detail readiness: declared "ready" once every ring has at
	# least one resident page (TR-SPEC-C3 fix). Simple bar; calibration
	# sprint 4.5 may refine to "all required pages resident".
	if not _full_detail and _all_rings_have_pages():
		_full_detail = true
		full_detail_ready.emit()


func _on_page_actually_evicted(ring: int, page_xz: Vector2) -> void:
	_page_load_times.erase(_page_key(ring, page_xz))
	page_unloaded.emit(ring, page_xz)
	# Demote full-detail if a ring just emptied (rare but possible
	# under aggressive LRU pressure).
	if _full_detail and not _all_rings_have_pages():
		_full_detail = false


func _bind_height_to_ring(ring: ClipmapRing,
		page: TerrainPageResult) -> void:
	var mat: Material = ring.mesh_instance.material_override
	if not (mat is ShaderMaterial):
		return
	# Convert PackedFloat32Array → ImageTexture for the shader uniform.
	# Phase 4.5 will swap to Texture2DRD via height_gpu capability so
	# the upload happens once on the render thread (TR-PERF-S2 path).
	var n: int = int(sqrt(page.height_cpu.size()))
	if n < 2:
		return
	var amp: float = ring_vertex_grid * 1.0  # safe upper bound
	if _kernel != null:
		amp = _kernel.amplitude
	# Normalize heights to [0, 1] for the shader's (h - 0.5) * 2 * scale
	# decoding (matches terrain_clipmap.gdshader's vertex math).
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * n * 4)  # RF format (single float per pixel)
	for i in range(page.height_cpu.size()):
		var h: float = page.height_cpu[i]
		var normalized: float = clamp((h / amp) * 0.5 + 0.5, 0.0, 1.0)
		bytes.encode_float(i * 4, normalized)
	var img: Image = Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_material_pipeline.bind_height_map(mat as ShaderMaterial, tex, amp, 0.0)


func _all_rings_have_pages() -> bool:
	if _rings.is_empty():
		return false
	# Each ring must have ≥ 1 page resident in its level
	var rings_seen: Dictionary = {}
	for k in _page_load_times.keys():
		rings_seen[_page_load_times[k]["ring"]] = true
	for i in range(_rings.size()):
		if not rings_seen.has(i):
			return false
	return true


func _page_key(ring: int, page_xz: Vector2) -> String:
	return "%d:%d:%d" % [ring, int(page_xz.x), int(page_xz.y)]
