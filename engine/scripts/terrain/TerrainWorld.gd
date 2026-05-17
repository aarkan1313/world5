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
# Per-ring multi-page heightmap state (Phase 4.9.a, audit C1 fix).
# Each ring has its own RingHeightArray maintaining a Texture2DArray
# of resident pages; vertex shader picks the right layer per fragment
# via world XZ → page coord → array layer.
var _ring_height_arrays: Array = []  # Array[RingHeightArray]

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
			Log.info("terrain_world", "sibling array built", {
				"slots": mv.slots.size(),
				"layers": sta.layer_count(),
				"materials_root": materials_root,
			})
			if sta.layer_count() > 0:
				_bind_slots_with_catalog(sta, mv, catalog)
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

	# Build the normalized height image for this page
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
		var normalized: float = clamp((h / amp) * 0.5 + 0.5, 0.0, 1.0)
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
		mv: MaterialVariants, catalog: BiomeCatalog) -> void:
	# Build per-slot windows + bands. We iterate over the manifest's
	# slot order (the order SiblingTextureArray packed the layers).
	# For each (biome, slot) in the manifest, look up the catalog
	# entry to get the selector bands. Missing catalog entry → use
	# very wide defaults (slot always active).
	var windows: Array = []
	var elev_bands: Array = []
	var slope_bands: Array = []
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

	Log.info("terrain_world", "binding slots on rings", {
		"slot_count": windows.size(),
		"has_catalog": catalog != null,
		"rings": _rings.size(),
	})

	# Phase 5.4.b audit C3 fix: bind per-tier sibling_blend_freq from
	# quality_tiers.json. Higher tiers afford finer-frequency noise =
	# less visible tile repeat at standing eye height.
	var tier: Dictionary = QualityTiers.get_tier(quality_tier_override) \
		if quality_tier_override != "" else QualityTiers.get_current()
	var blend_freq: float = float(tier.get("terrain_sibling_blend_freq", 0.30))

	for ring in _rings:
		var rmat: Material = ring.mesh_instance.material_override
		if rmat is ShaderMaterial:
			_material_pipeline.bind_all_slots(rmat as ShaderMaterial,
				sta.texture, windows, elev_bands, slope_bands)
			_material_pipeline.bind_sibling_blend_freq(
				rmat as ShaderMaterial, blend_freq)


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
