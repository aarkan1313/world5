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

# Bookkeeping
var _camera: Node3D = null
var _loaded: bool = false
var _full_detail: bool = false


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

	# 1. Snap rings to camera (per-ring cell-aligned)
	_dispatch.update(_rings, cam_pos)

	# 2. Compute morph factor per ring + push to material
	for i in range(_rings.size()):
		var ring: ClipmapRing = _rings[i]
		var half_extent: float = float(ring_vertex_grid - 1) * ring.cell_size_m * 0.5
		var morph: float = _dispatch.compute_morph_factor(
			Vector2(cam_pos.x, cam_pos.z),
			ring.snapped_center,
			half_extent,
			morph_band_fraction,
		)
		var mat: Material = ring.mesh_instance.material_override
		if mat is ShaderMaterial:
			_material_pipeline.set_morph_factor(mat as ShaderMaterial, morph)

	# 3. Compute required page set across all rings + push to residency
	var required: Array = []
	for i in range(_rings.size()):
		var ring: ClipmapRing = _rings[i]
		var ring_extent: float = float(ring_vertex_grid - 1) * ring.cell_size_m
		required.append_array(_residency.required_pages_for_ring(
			Vector2(cam_pos.x, cam_pos.z), i, ring_extent))
	_residency.update(required)


# --- public API ---

func is_full_detail_ready() -> bool:
	return _full_detail


func get_resident_pages() -> Array:
	if _cache == null:
		return []
	# Returns just count + bytes for now; per-page detail in 4.6
	return [{"count": _cache.size(), "bytes": _cache.total_bytes()}]


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

	# ResidencyManager + PageStreamingJob are Nodes — children of self
	_residency = ResidencyManager.new()
	_residency.name = "ResidencyManager"
	_residency.configure(_cache, page_extent_m)
	add_child(_residency)

	_streaming = PageStreamingJob.new()
	_streaming.name = "PageStreamingJob"
	_streaming.configure(_adapter, _cache)
	add_child(_streaming)

	# Wire residency → streaming
	_residency.page_load_requested.connect(_streaming.on_load_requested)
	_residency.page_evict_requested.connect(_streaming.on_evict_requested)
	# Re-emit to public signals
	_residency.page_load_requested.connect(_on_page_load_requested)
	_residency.page_evict_requested.connect(_on_page_evict_requested)

	# Build rings + materials
	var meshes: Array = _geometry.build(ring_count, ring_vertex_grid,
		inner_cell_size_m)
	for i in range(meshes.size()):
		var ring: ClipmapRing = ClipmapRing.new()
		ring.configure(meshes[i], i, inner_cell_size_m * pow(2.0, i))
		var mat: ShaderMaterial = _material_pipeline.make_ring_material(i)
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
	# Phase 4.4 ships a minimal loader: just macro albedo + surface_slots
	# if present. Phase 4.6 expands to biome_catalog + kernels per spec 14.
	var macro_cfg: String = bundle_path + "macro_albedo.json"
	if FileAccess.file_exists(macro_cfg):
		_macro.load_from_path(macro_cfg)
		for ring in _rings:
			var mat: Material = ring.mesh_instance.material_override
			if mat is ShaderMaterial:
				_material_pipeline.bind_macro_albedo(mat as ShaderMaterial, _macro)
	var slots_cfg: String = bundle_path + "surface_slots.json"
	if FileAccess.file_exists(slots_cfg):
		_slots.load_from_path(slots_cfg)

	_loaded = true
	world_loaded.emit()


func _exit_tree() -> void:
	# Per spec 08a rule 5: free GPU resources BEFORE the autoload
	# tracker tears down. Adapter holds the cached shader RID.
	if _adapter != null:
		_adapter.shutdown()
	if _loaded:
		world_unloaded.emit()


# --- signal relays ---

func _on_page_load_requested(ring: int, page_xz: Vector2) -> void:
	# We can't observe the actual completion of the load here cheaply;
	# emit the public signal on the request so consumers know SOMETHING
	# is streaming. Phase 4.6 wires a "page actually cached" path.
	page_loaded.emit(ring, page_xz)


func _on_page_evict_requested(ring: int, page_xz: Vector2) -> void:
	page_unloaded.emit(ring, page_xz)
