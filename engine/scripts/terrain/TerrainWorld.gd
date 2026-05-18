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


# Runtime defaults. If scene exports are left at these values,
# QualityTiers may replace them before modules are built.
const DEFAULT_RING_COUNT: int = 6
const DEFAULT_RING_VERTEX_GRID: int = 256
const DEFAULT_INNER_CELL_SIZE_M: float = 0.5
const DEFAULT_TERRAIN_PAGES_MAX: int = 64
const DEFAULT_TERRAIN_HAZE_COLOR: Color = Color(0.646, 0.656, 0.674, 1.0)
const DEFAULT_TERRAIN_HAZE_STRENGTH: float = 0.70


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
# Per-ring multi-page heightmap state (Phase 4.9.a, audit C1 fix).
# Each ring has its own RingHeightArray maintaining a Texture2DArray
# of resident pages; vertex shader picks the right layer per fragment
# via world XZ → page coord → array layer.
var _ring_height_arrays: Array = []  # Array[RingHeightArray]

# Bookkeeping
var _camera: Node3D = null
var _loaded: bool = false
var _full_detail: bool = false
# Last required page-set signature sent to ResidencyManager. The visible
# ring footprint can enter a new page before the camera's own page changes,
# so dirty-check the actual requirements, not just camera page coord.
var _last_residency_signature: String = ""
# Page bookkeeping for full-detail readiness check + spec'd
# get_resident_pages() shape (TR-SPEC-C3 + TR-SPEC-S1).
# Key = "ring:x:z" → {ring, xz, age_ms}
var _page_load_times: Dictionary = {}


# --- lifecycle ---

func _ready() -> void:
	_apply_quality_tier_defaults()
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

	# 2. Phase 4.10.a (W4 PITFALLS #11 fix): bind per-ring morph
	# geometry so the vertex shader computes per-vertex morph factor.
	# Pre-fix: single per-ring morph_factor uniform was driven by
	# camera-to-ring-CENTER distance — all vertices got the same value,
	# outer-edge vertices never morphed when camera was near center →
	# visible cliff at ring boundary. Now the shader does its own math.
	#
	# Outermost ring has no parent to morph toward — pass half_extent=0
	# so the shader's morph is a no-op (m stays 0). Inner rings morph
	# toward the (single-step coarser via 2× cell snap) approximation.
	var outermost: int = _rings.size() - 1
	for i in range(_rings.size()):
		var ring: ClipmapRing = _rings[i]
		var half_extent: float = float(ring_vertex_grid - 1) * ring.cell_size_m * 0.5
		var mat: Material = ring.mesh_instance.material_override
		if mat is ShaderMaterial:
			if i == outermost:
				_material_pipeline.set_ring_morph(mat as ShaderMaterial,
					ring.snapped_center, 0.0, 0.0)
			else:
				_material_pipeline.set_ring_morph(mat as ShaderMaterial,
					ring.snapped_center, half_extent, morph_band_fraction)

	# 3. Residency update. Dirty-check the actual required page set.
	# A ring can expose a new edge page while the camera is still inside
	# the same page; checking only camera page coord leaves flat placeholder
	# layers visible until the player crosses the page boundary.
	var required: Array = _required_pages_for_camera(cam_xz)
	var residency_signature: String = _required_pages_signature(required)
	if residency_signature != _last_residency_signature:
		_last_residency_signature = residency_signature
		_residency.update(required)


func _required_pages_for_camera(cam_xz: Vector2) -> Array:
	var required: Array = []
	for i in range(_rings.size()):
		var ring: ClipmapRing = _rings[i]
		var ring_extent: float = float(ring_vertex_grid - 1) * ring.cell_size_m
		required.append_array(_residency.required_pages_for_ring(
			cam_xz, i, ring_extent))
	return required


func _required_pages_signature(required: Array) -> String:
	var out: String = ""
	for i in range(required.size()):
		var entry: Dictionary = required[i]
		var xz: Vector2 = entry["xz"]
		if i > 0:
			out += "|"
		out += "%d:%d:%d" % [
			int(entry["ring"]),
			int(xz.x),
			int(xz.y),
		]
	return out


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


func _active_quality_tier() -> Dictionary:
	return QualityTiers.get_tier(quality_tier_override) \
		if quality_tier_override != "" else QualityTiers.get_current()


func _active_quality_tier_name() -> String:
	var tier: Dictionary = _active_quality_tier()
	return String(tier.get("tier_name", "high"))


func _apply_quality_tier_defaults() -> void:
	var tier: Dictionary = _active_quality_tier()
	if tier.is_empty():
		return

	# Preserve deliberate scene/test overrides. The tier fills only the
	# exported defaults that would otherwise drift from quality_tiers.json.
	if ring_count == DEFAULT_RING_COUNT:
		ring_count = int(tier.get("terrain_rings", ring_count))
	if ring_vertex_grid == DEFAULT_RING_VERTEX_GRID:
		ring_vertex_grid = int(tier.get("terrain_grid_n", ring_vertex_grid))
	if is_equal_approx(inner_cell_size_m, DEFAULT_INNER_CELL_SIZE_M):
		inner_cell_size_m = float(tier.get("terrain_step0_m", inner_cell_size_m))
	if terrain_pages_max == DEFAULT_TERRAIN_PAGES_MAX:
		terrain_pages_max = int(tier.get(
			"streaming_budget_cpu_pages", terrain_pages_max))


# --- module construction ---

func _build_modules() -> void:
	_geometry = ClipmapGeometry.new()
	_dispatch = ClipmapDispatch.new()
	_cache = TerrainPageCache.new()
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
		0, _active_quality_tier_name(), _kernel, ["height_cpu"])
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
		var ring_cell_m: float = inner_cell_size_m * pow(2.0, i)
		ring.configure(meshes[i], i, ring_cell_m)
		var mat: ShaderMaterial = _material_pipeline.make_ring_material(
			i, ring_vertex_grid)
		ring.mesh_instance.material_override = mat
		add_child(ring.mesh_instance)
		_rings.append(ring)
		# Phase 4.9.a multi-page heightmap: one RingHeightArray per ring.
		# Ring extent = (grid_n - 1) * cell_size_m; conservative pages_per_side
		# computed inside RingHeightArray.configure().
		var rha: RingHeightArray = RingHeightArray.new()
		var ring_extent_m: float = float(ring_vertex_grid - 1) * ring_cell_m
		rha.configure(ring_extent_m, page_extent_m)
		_ring_height_arrays.append(rha)

	var min_visible_pages: int = _minimum_visible_height_pages()
	if terrain_pages_max > 0 and terrain_pages_max < min_visible_pages:
		Log.info("terrain_world",
			"raising terrain page cache budget to visible height working set",
			{"configured": terrain_pages_max, "required": min_visible_pages})
		_cache.set_budget(min_visible_pages)
	else:
		_cache.set_budget(terrain_pages_max)

	_bind_terrain_haze_from_tier()

	# Diagnostics overlay (off by default per @export var)
	_diag = RingDebugOverlay.new()
	_diag.name = "RingDebugOverlay"
	add_child(_diag)
	_diag.bind_rings(_rings)
	_diag.set_enabled(debug_overlay)


func _minimum_visible_height_pages() -> int:
	var total: int = 0
	for rha in _ring_height_arrays:
		var pages: int = int(rha.pages_per_side)
		total += pages * pages
	return total


func _outer_terrain_radius_m() -> float:
	if ring_count <= 0:
		return 0.0
	return float(ring_vertex_grid - 1) * inner_cell_size_m \
		* pow(2.0, ring_count - 1) * 0.5


func _bind_terrain_haze_from_tier() -> void:
	var tier: Dictionary = _active_quality_tier()
	if tier.is_empty():
		return
	var outer_radius: float = _outer_terrain_radius_m()
	if outer_radius <= 0.0:
		return
	var visibility_m: float = float(tier.get(
		"visibility_ship_distance_m", outer_radius))
	var haze_basis: float = min(max(visibility_m, 0.0), outer_radius)
	if haze_basis <= 0.0:
		return

	var start_frac: float = clamp(float(tier.get(
		"visibility_haze_start_fraction", 0.65)), 0.0, 1.0)
	var end_frac: float = clamp(float(tier.get(
		"visibility_haze_end_fraction", 1.0)), 0.0, 1.0)
	var haze_start_m: float = haze_basis * min(start_frac, end_frac)
	var haze_end_m: float = max(haze_start_m + 0.01, haze_basis * end_frac)
	for ring in _rings:
		var mat: Material = ring.mesh_instance.material_override
		if mat is ShaderMaterial:
			_material_pipeline.bind_terrain_haze(mat as ShaderMaterial,
				true, haze_start_m, haze_end_m,
				DEFAULT_TERRAIN_HAZE_STRENGTH, DEFAULT_TERRAIN_HAZE_COLOR)


# --- world bundle loading ---

func _load_world_bundle(bundle_path: String) -> void:
	# Phase 4.4 ships a minimal loader: macro albedo + surface_slots +
	# noise_stack kernel if present. Phase 4.6 expands to biome_catalog
	# per spec 14. Missing files are logged warn (TR-SPEC-S2 fix —
	# was silently no-op).
	var mv_cfg: String = bundle_path + "material_variants.json"
	var has_material_variants: bool = FileAccess.file_exists(mv_cfg)
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
		if not has_material_variants:
			Log.warn("terrain_world", "bundle missing macro_albedo.json",
				{"bundle": bundle_path})
		else:
			Log.info("terrain_world", "bundle omits optional macro_albedo.json",
				{"bundle": bundle_path})

	var slots_cfg: String = bundle_path + "surface_slots.json"
	if FileAccess.file_exists(slots_cfg):
		if not _slots.load_from_path(slots_cfg):
			Log.warn("terrain_world", "surface_slots.json failed to load",
				{"path": slots_cfg})

	# --- biome_catalog (spec 22) → per-slot selectors for Phase 4.9.b ---
	#
	# When the bundle ships a biome_catalog.json, the per-slot elevation
	# + slope bands drive per-fragment slot weight in the shader.
	# Without a catalog, fall back to legacy single-slot binding.
	var catalog: BiomeCatalog = null
	var catalog_cfg: String = bundle_path + "biome_catalog.json"
	if FileAccess.file_exists(catalog_cfg):
		catalog = BiomeCatalog.from_file(catalog_cfg)
		if catalog != null:
			var cat_errors: Array = catalog.validate()
			if cat_errors.size() > 0:
				Log.warn("terrain_world", "biome_catalog validation errors",
					{"errors": cat_errors})

	# --- spec 24 Layer 1 (siblings + per-fragment slot selection) ---
	#
	# Phase 4.9.b: build the sibling Texture2DArray from material_variants,
	# extract per-slot (start, count) windows + elev/slope bands from
	# the biome catalog, bind ALL slots so the shader's per-fragment
	# loop can weight + blend across them.
	# Fallback (no catalog OR no slot selectors): legacy single-slot
	# binding via bind_sibling_array — preserves Phase 5.5 behavior
	# for any scene that hasn't migrated.
	if has_material_variants:
		var mv: MaterialVariants = MaterialVariants.from_file(mv_cfg)
		if mv != null and mv.slots.size() > 0:
			var materials_root: String = bundle_path + "materials"
			var sta: SiblingTextureArray = SiblingTextureArray.build(
				mv, materials_root, "albedo")
			# Parallel T_inv LUT array for Heitz-Neyret histogram
			# preservation. Layer-matched 1:1 with `sta`; each entry is
			# a 256×1 inverse-CDF LUT generated by tx_hn_lut.py. Missing
			# albedo_tinv.png → empty array → shader falls back to plain
			# weighted HN blend (still anti-repeat, loses contrast).
			var sta_tinv: SiblingTextureArray = SiblingTextureArray.build(
				mv, materials_root, "albedo_tinv")
			var sta_normal: SiblingTextureArray = SiblingTextureArray.build(
				mv, materials_root, "normal")
			var sta_roughness: SiblingTextureArray = SiblingTextureArray.build(
				mv, materials_root, "roughness")
			var sta_ao: SiblingTextureArray = SiblingTextureArray.build(
				mv, materials_root, "ao")
			Log.info("terrain_world", "sibling array built", {
				"slots": mv.slots.size(),
				"layers": sta.layer_count(),
				"tinv_layers": sta_tinv.layer_count(),
				"normal_layers": sta_normal.layer_count(),
				"roughness_layers": sta_roughness.layer_count(),
				"ao_layers": sta_ao.layer_count(),
				"materials_root": materials_root,
			})
			if sta.layer_count() > 0:
				_bind_slots_with_catalog(sta, sta_tinv, mv, catalog,
					materials_root, sta_normal, sta_roughness, sta_ao)
	else:
		Log.warn("terrain_world", "bundle missing material_variants.json",
			{"path": mv_cfg})

	# --- spec 24 Layer 2 (detail overlays) ---
	#
	# detail_array.json lives per-biome under materials/biome_<biome>/.
	# For single-biome walking demo we bind the first biome we find.
	# Phase 6 multi-biome will need to pick the biome dynamically.
	if mv_cfg != "" and FileAccess.file_exists(mv_cfg):
		var materials_dir: String = bundle_path + "materials"
		if DirAccess.dir_exists_absolute(
				ProjectSettings.globalize_path(materials_dir)):
			var d: DirAccess = DirAccess.open(materials_dir)
			if d != null:
				d.list_dir_begin()
				var entry: String = d.get_next()
				while entry != "":
					if d.current_is_dir() and entry.begins_with("biome_"):
						var biome: String = entry.substr(len("biome_"))
						var da_cfg: String = "%s/%s/detail_array.json" % [
							materials_dir, entry]
						if FileAccess.file_exists(da_cfg):
							var da: DetailArray = DetailArray.from_file(da_cfg)
							if da != null and da.tile_count() > 0:
								var dta: DetailTextureArray = DetailTextureArray.build(
									da, materials_dir, "albedo")
								if dta.layer_count() > 0:
									for ring in _rings:
										var rmat2: Material = ring.mesh_instance.material_override
										if rmat2 is ShaderMaterial:
											_material_pipeline.bind_detail_array(
												rmat2 as ShaderMaterial,
												dta.texture, dta.layer_count())
									# Only bind the first biome that has
									# detail (single-biome walking demo)
									break
					entry = d.get_next()
				d.list_dir_end()

	# Kernel config. Two-tier precedence (Phase 6 follow-up):
	#   1. Catalog kernel chain (per biome `kernel` field, parsed by
	#      KernelComposer). This is the modern path — enables erosion
	#      stages, future DEM features, per-biome divergent chains.
	#      Walking demo's alpine biome ships a noise+erosion chain.
	#   2. Legacy single-noise kernels/noise_stack.json. Pre-catalog
	#      bundles still work; bundle authors can omit it once their
	#      catalog declares a kernel chain.
	var composer: KernelComposer = null
	if catalog != null and catalog.biomes.size() > 0:
		# First biome's chain wins for the demo's single-page-set
		# generation. Per-biome divergent chains land alongside the
		# Composer's per-biome blending (spec 19 §"KernelComposer"
		# multi-biome height blend, not yet wired runtime-side).
		var first_biome: Dictionary = catalog.biomes[0]
		var kernel_spec: Variant = first_biome.get("kernel", null)
		if kernel_spec is Dictionary:
			composer = KernelComposer.from_dict(kernel_spec)
			var cerrs: Array = composer.validate()
			if cerrs.size() > 0:
				Log.warn("terrain_world", "kernel chain validation",
					{"biome": first_biome.get("name", ""), "errors": cerrs})
			else:
				Log.info("terrain_world", "kernel chain loaded", {
					"biome": first_biome.get("name", ""),
					"stages": composer.stages.size(),
					"chain_hash": composer.chain_hash().substr(0, 12),
				})
				# Keep _kernel for back-compat introspection (tests +
				# diagnostics still read it).
				_kernel = composer.base_noise_kernel()

	var kernel_cfg: String = bundle_path + "kernels/noise_stack.json"
	if composer == null and FileAccess.file_exists(kernel_cfg):
		# Legacy path — no catalog chain, fall back to standalone JSON.
		var f: FileAccess = FileAccess.open(kernel_cfg, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_kernel = NoiseStackKernel.from_dict(parsed)

	# Re-configure streaming with whichever kernel source won.
	if _streaming != null and (composer != null or _kernel != null):
		_streaming.configure(_adapter, _cache, page_extent_m,
			ring_vertex_grid, 0, "high", _kernel, ["height_cpu"], composer)

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
	# Phase 4.9.a: bind the loaded page into the ring's RingHeightArray
	# (multi-page), then rebuild + push the Texture2DArray to the
	# material. Replaces the pre-4.9.a single-page-per-ring binding
	# which stretched outer-ring textures at edges (audit C1).
	if ring >= 0 and ring < _rings.size():
		var page: TerrainPageResult = _cache.get_page(ring, page_xz)
		if page != null and not page.height_cpu.is_empty():
			_update_ring_height_array(ring, page_xz, page)

	page_loaded.emit(ring, page_xz)

	# Full-detail readiness: declared "ready" once every ring has at
	# least one resident page (TR-SPEC-C3 fix). Simple bar; calibration
	# sprint 4.5 may refine to "all required pages resident".
	if not _full_detail and _all_rings_have_pages():
		_full_detail = true
		full_detail_ready.emit()


func _on_page_actually_evicted(ring: int, page_xz: Vector2) -> void:
	_page_load_times.erase(_page_key(ring, page_xz))
	# Phase 4.9.a: remove from the ring's array + rebuild.
	if ring >= 0 and ring < _ring_height_arrays.size():
		var rha: RingHeightArray = _ring_height_arrays[ring]
		rha.remove_page(page_xz)
		_rebuild_and_bind_ring_height_array(ring)
	page_unloaded.emit(ring, page_xz)
	# Demote full-detail if a ring just emptied (rare but possible
	# under aggressive LRU pressure).
	if _full_detail and not _all_rings_have_pages():
		_full_detail = false


## Add a freshly-loaded page to the ring's height array + rebuild +
## bind the new Texture2DArray. Phase 4.9.a replacement for
## _bind_height_to_ring (single-page).
func _update_ring_height_array(ring_idx: int, page_xz: Vector2,
		page: TerrainPageResult) -> void:
	var rha: RingHeightArray = _ring_height_arrays[ring_idx]
	var ring: ClipmapRing = _rings[ring_idx]
	# Anchor the array's min_xz to the ring's CURRENT snapped center
	# (the ring extent on each side of snapped_center). Floor to page
	# boundary so page coords align with the world page grid.
	var ring_extent_m: float = float(ring_vertex_grid - 1) * ring.cell_size_m
	var raw_min: Vector2 = ring.snapped_center - Vector2(ring_extent_m, ring_extent_m) * 0.5
	var aligned_min: Vector2 = Vector2(
		floor(raw_min.x / page_extent_m) * page_extent_m,
		floor(raw_min.y / page_extent_m) * page_extent_m,
	)
	# Phase 4.10.b (W4 PITFALLS #14 fix): on ring snap, REBASE the
	# existing array to the new min_xz instead of dropping everything.
	# Pages still in the new window keep their image content + get
	# remapped to new local coords; out-of-window pages are evicted.
	# Pre-fix: full drop forced every page to re-stream from scratch
	# → "rings visible while walking" symptom.
	if aligned_min != rha.min_xz:
		if rha.layer_count() > 0:
			rha.rebase(aligned_min)
		else:
			rha.set_min_corner(aligned_min)
	else:
		rha.set_min_corner(aligned_min)

	# Build the normalized height image for this page.
	# Phase 4.11.a: dropped the [0,1] clamp. Pre-fix, fBm noise peaks
	# beyond ±amplitude clamped to 0/1 = flat plateau with sharp
	# straight-edge level-set boundaries visible in walking demo
	# screenshots. Float32 texture stores arbitrary range fine; shader
	# decode `(h - 0.5) * 2 * height_scale` handles out-of-[0,1] values
	# correctly (just produces y beyond ±amplitude). Bilinear filter
	# between in-range and out-of-range values is well-defined.
	var n: int = int(sqrt(page.height_cpu.size()))
	if n < 2:
		return
	var amp: float = ring_vertex_grid * 1.0  # safe upper bound
	if _kernel != null:
		amp = _kernel.amplitude
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * n * 4)
	for i in range(page.height_cpu.size()):
		var h: float = page.height_cpu[i]
		var normalized: float = (h / amp) * 0.5 + 0.5
		bytes.encode_float(i * 4, normalized)
	var img: Image = Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
	rha.add_page(page_xz, img)
	_rebuild_and_bind_ring_height_array(ring_idx)


func _rebuild_and_bind_ring_height_array(ring_idx: int) -> void:
	var rha: RingHeightArray = _ring_height_arrays[ring_idx]
	var ring: ClipmapRing = _rings[ring_idx]
	var mat: Material = ring.mesh_instance.material_override
	if not (mat is ShaderMaterial):
		return
	var amp: float = ring_vertex_grid * 1.0
	if _kernel != null:
		amp = _kernel.amplitude
	var tex: Texture2DArray = rha.build_texture_array()
	if tex == null:
		# No pages resident yet; leave material in unbound state
		return
	_material_pipeline.bind_height_array(mat as ShaderMaterial, tex,
		rha.pages_per_side, rha.min_xz, rha.page_extent_m, amp, 0.0)


## Bind every slot's sibling window + selector bands on every ring
## material. Phase 4.9.b. Falls back to legacy single-slot binding
## when the catalog isn't available OR when a catalog slot has no
## matching variants in the manifest (avoids breaking demos that
## have textures but no catalog yet).
func _bind_slots_with_catalog(sta: SiblingTextureArray,
		sta_tinv: SiblingTextureArray,
		mv: MaterialVariants, catalog: BiomeCatalog,
		materials_root: String = "",
		sta_normal: SiblingTextureArray = null,
		sta_roughness: SiblingTextureArray = null,
		sta_ao: SiblingTextureArray = null) -> void:
	# Build per-slot windows + bands. We iterate over the manifest's
	# slot order (the order SiblingTextureArray packed the layers).
	# For each (biome, slot) in the manifest, look up the catalog
	# entry to get the selector bands. Missing catalog entry → use
	# very wide defaults (slot always active).
	#
	# Phase 6 (5.7.b GDScript Composer mirror): also collect per-biome
	# auto_rules + per-slot biome_index so the fragment shader can
	# multiply each slot's weight by its biome's auto_rule weight.
	# Result: multi-biome scenes render the correct biome's slots per
	# fragment.
	var windows: Array = []
	var elev_bands: Array = []
	var slope_bands: Array = []
	var slot_biome_indices: Array = []
	# Track biome name → composer-style index. First-seen order.
	var biome_name_to_idx: Dictionary = {}
	for slot_entry in mv.slots:
		if not (slot_entry is Dictionary):
			continue
		var se: Dictionary = slot_entry
		var biome_name: String = String(se.get("biome", ""))
		var slot_name: String = String(se.get("slot", ""))
		var win: Dictionary = sta.window_for(biome_name, slot_name)
		if int(win.get("count", 0)) <= 0:
			continue  # SiblingTextureArray.build skipped this slot
		windows.append({"start": int(win["start"]), "count": int(win["count"])})
		var elev_b: Dictionary = {
			"min": -10000.0, "max": 10000.0, "band_min": 1.0, "band_max": 1.0
		}
		var slope_b: Dictionary = {
			"min": 0.0, "max": 90.0, "band_min": 1.0, "band_max": 1.0
		}
		if catalog != null:
			var biome: Dictionary = catalog.biome_by_name(biome_name)
			for cs in (biome.get("surface_slots", []) as Array):
				if not (cs is Dictionary):
					continue
				var csd: Dictionary = cs
				if String(csd.get("name", "")) != slot_name:
					continue
				var sel: Dictionary = csd.get("selector", {})
				if sel.has("elevation_m") and (sel["elevation_m"] as Array).size() == 2:
					elev_b["min"] = float((sel["elevation_m"] as Array)[0])
					elev_b["max"] = float((sel["elevation_m"] as Array)[1])
				if sel.has("slope_deg") and (sel["slope_deg"] as Array).size() == 2:
					slope_b["min"] = float((sel["slope_deg"] as Array)[0])
					slope_b["max"] = float((sel["slope_deg"] as Array)[1])
				if sel.has("band_width_elevation_m"):
					var bwe: float = float(sel["band_width_elevation_m"])
					elev_b["band_min"] = bwe
					elev_b["band_max"] = bwe
				if sel.has("band_width_slope_deg"):
					var bws: float = float(sel["band_width_slope_deg"])
					slope_b["band_min"] = bws
					slope_b["band_max"] = bws
				break
		elev_bands.append(elev_b)
		slope_bands.append(slope_b)
		# Assign biome index in first-seen order (matches the composer's
		# `biome_names` ordering when loaded from the same catalog).
		if not biome_name_to_idx.has(biome_name):
			biome_name_to_idx[biome_name] = biome_name_to_idx.size()
		slot_biome_indices.append(int(biome_name_to_idx[biome_name]))

	# Collect per-biome auto_biome_rules in the same first-seen order.
	# Missing auto_rules → always-on default (biome wins everywhere).
	var biome_count: int = biome_name_to_idx.size()
	var biome_elev_bands: Array = []
	var biome_slope_bands: Array = []
	# Single-biome scenes don't need per-biome multiply; pass count=0
	# so the shader skips the biome step entirely (back-compat).
	var enable_biome_weights: bool = biome_count > 1 and catalog != null
	if enable_biome_weights:
		var ordered_names: Array = biome_name_to_idx.keys()
		# Dictionary.keys() preserves insertion order in Godot 4.
		for biome_name_2 in ordered_names:
			var biome2: Dictionary = catalog.biome_by_name(String(biome_name_2))
			var auto: Dictionary = biome2.get("auto_biome_rules", {})
			var e_band: Dictionary = {
				"min": -10000.0, "max": 10000.0,
				"band_min": 1.0, "band_max": 1.0,
			}
			var s_band: Dictionary = {
				"min": 0.0, "max": 90.0,
				"band_min": 1.0, "band_max": 1.0,
			}
			if auto.has("elevation_m") and (auto["elevation_m"] as Array).size() == 2:
				e_band["min"] = float((auto["elevation_m"] as Array)[0])
				e_band["max"] = float((auto["elevation_m"] as Array)[1])
			if auto.has("slope_deg") and (auto["slope_deg"] as Array).size() == 2:
				s_band["min"] = float((auto["slope_deg"] as Array)[0])
				s_band["max"] = float((auto["slope_deg"] as Array)[1])
			if auto.has("band_width_elevation_m"):
				var bwe2: float = float(auto["band_width_elevation_m"])
				e_band["band_min"] = bwe2
				e_band["band_max"] = bwe2
			if auto.has("band_width_slope_deg"):
				var bws2: float = float(auto["band_width_slope_deg"])
				s_band["band_min"] = bws2
				s_band["band_max"] = bws2
			biome_elev_bands.append(e_band)
			biome_slope_bands.append(s_band)

	Log.info("terrain_world", "binding slots on rings", {
		"slot_count": windows.size(),
		"biome_count": biome_count,
		"biome_weights_active": enable_biome_weights,
		"has_catalog": catalog != null,
		"rings": _rings.size(),
		"region_size_m": mv.region_size_m,
		"edge_blend_m": mv.edge_blend_m,
		"world_seed": mv.world_seed,
	})

	# Phase 5.4.b audit C3 fix: bind per-tier sibling_blend_freq from
	# quality_tiers.json. Higher tiers afford finer-frequency noise =
	# less visible tile repeat at standing eye height.
	var tier: Dictionary = _active_quality_tier()
	var blend_freq: float = float(tier.get("terrain_sibling_blend_freq", 0.30))
	var tile_size_m: float = float(tier.get("terrain_pbr_tile_size_m", 8.0))
	var normal_array: Texture2DArray = _matched_sibling_texture_or_null(
		sta, sta_normal, "normal")
	var roughness_array: Texture2DArray = _matched_sibling_texture_or_null(
		sta, sta_roughness, "roughness")
	var ao_array: Texture2DArray = _matched_sibling_texture_or_null(
		sta, sta_ao, "ao")

	# Phase 6 visual A/B 2026-05-17: per-biome ground avg color → shader
	# per-fragment biome-weighted fallback. Replaces the single global
	# olive `fallback_color` so coverage gaps (no slot wins) read as
	# neighbor-biome ground instead of olive green. Loads each biome's
	# ground albedo, downscales to 1×1, reads the avg. ~1ms total per
	# bundle load.
	var fallback_colors: Array = []
	if enable_biome_weights and materials_root != "":
		var ordered_names: Array = biome_name_to_idx.keys()
		for biome_name_3 in ordered_names:
			fallback_colors.append(_compute_biome_ground_avg(
				String(biome_name_3), materials_root))

	for ring in _rings:
		var rmat: Material = ring.mesh_instance.material_override
		if rmat is ShaderMaterial:
			_material_pipeline.bind_all_slots(rmat as ShaderMaterial,
				sta.texture, windows, elev_bands, slope_bands,
				slot_biome_indices)
			_material_pipeline.bind_sibling_blend_freq(
				rmat as ShaderMaterial, blend_freq)
			_material_pipeline.bind_sibling_tile_size_m(
				rmat as ShaderMaterial, tile_size_m)
			_material_pipeline.bind_sibling_pbr_arrays(
				rmat as ShaderMaterial,
				normal_array, roughness_array, ao_array)
			# Phase 6 follow-up: region + Heitz-Neyret sampler config.
			# region_size_m + edge_blend_m + world_seed read from manifest.
			_material_pipeline.bind_variety_combined(
				rmat as ShaderMaterial,
				sta_tinv.texture if sta_tinv.layer_count() > 0 else null,
				mv.region_size_m, mv.edge_blend_m, mv.world_seed)
			if enable_biome_weights:
				_material_pipeline.bind_biome_auto_rules(
					rmat as ShaderMaterial, biome_count,
					biome_elev_bands, biome_slope_bands)
				_material_pipeline.bind_biome_fallback_colors(
					rmat as ShaderMaterial, fallback_colors)
			else:
				_material_pipeline.bind_biome_auto_rules(
					rmat as ShaderMaterial, 0, [], [])
				_material_pipeline.bind_biome_fallback_colors(
					rmat as ShaderMaterial, [])


func _matched_sibling_texture_or_null(albedo_sta: SiblingTextureArray,
		pbr_sta: SiblingTextureArray, map_name: String) -> Texture2DArray:
	if albedo_sta == null or pbr_sta == null:
		return null
	if pbr_sta.layer_count() <= 0:
		return null
	if pbr_sta.layer_count() != albedo_sta.layer_count():
		Log.warn("terrain_world", "sibling PBR layer mismatch", {
			"map": map_name,
			"albedo_layers": albedo_sta.layer_count(),
			"pbr_layers": pbr_sta.layer_count(),
		})
		return null
	if not _sibling_windows_match(albedo_sta.slot_windows, pbr_sta.slot_windows):
		Log.warn("terrain_world", "sibling PBR window mismatch", {
			"map": map_name,
		})
		return null
	return pbr_sta.texture


func _sibling_windows_match(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not (a[i] is Dictionary) or not (b[i] is Dictionary):
			return false
		var aw: Dictionary = a[i]
		var bw: Dictionary = b[i]
		if String(aw.get("biome", "")) != String(bw.get("biome", "")):
			return false
		if String(aw.get("slot", "")) != String(bw.get("slot", "")):
			return false
		if int(aw.get("start", -1)) != int(bw.get("start", -1)):
			return false
		if int(aw.get("count", -1)) != int(bw.get("count", -1)):
			return false
	return true


func _compute_biome_ground_avg(biome_name: String,
		materials_root: String) -> Color:
	# Read biome_<name>/ground/albedo.png, downscale to 1×1, return color.
	# Falls back to mid-grey on any error so the shader still gets a
	# usable fallback (no black holes).
	var path: String = "%s/biome_%s/ground/albedo.png" % [
		materials_root, biome_name]
	var img: Image = Image.load_from_file(
		ProjectSettings.globalize_path(path))
	if img == null:
		Log.warn("terrain_world", "biome ground avg load failed", {
			"biome": biome_name, "path": path})
		return Color(0.5, 0.5, 0.5)
	img.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	return img.get_pixel(0, 0)


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
