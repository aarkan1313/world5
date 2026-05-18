## MaterialPipeline — owns the per-ring ShaderMaterial + binds
## heightmap, macro albedo, ring uniforms.
##
## Per spec 21 module decomposition + spec 24 layers. Phase 4 shipped
## Layer 3 (macro). Phase 5.5 added Layer 1 (sibling array, 3-tap
## stochastic UV blend) — opt-in via bind_sibling_array(); unbound
## materials still render the pre-5.5 macro-only path so the walking
## demo works before textures arrive.

class_name MaterialPipeline extends RefCounted


const SHADER_PATH := "res://addons/world5/shaders/terrain_clipmap.gdshader"
# Spec 24 shader cap: max_variants_per_slot = 8 (3-tap blend budget +
# room for selection bias). Binder enforces so authoring overflow
# fails loud here rather than silently overflowing the shader.
const SIBLING_COUNT_CAP: int = 8
# Spec 23 hard cap: max slots per biome = 8 (shader's per-fragment
# slot loop budget). Phase 4.9.b adds per-fragment slot selection.
const MAX_SLOTS: int = 8
# Spec 22 hard cap: max biomes per world = 8 (shader's per-fragment
# biome_weight loop budget; matches MAX_SLOTS for symmetric uniform
# arrays). Phase 6 / 5.7.b GDScript Composer mirror.
const MAX_BIOMES: int = 8


# Lazily-loaded Shader resource shared across all ring materials
var _shader: Shader = null


## Construct a fresh ShaderMaterial for the given ring index.
## Independent materials per ring so each can hold its own morph
## factor + heightmap (Phase 4.4.d composer wires them).
func make_ring_material(_ring_index: int,
		grid_n: int = 256) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER_PATH)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _shader
	# Sensible defaults so the material renders SOMETHING even before
	# the composer binds real assets
	mat.set_shader_parameter("height_scale", 50.0)
	mat.set_shader_parameter("height_offset", 0.0)
	mat.set_shader_parameter("ring_center_xz", Vector2(0.0, 0.0))
	mat.set_shader_parameter("ring_half_extent_m", 1.0)
	mat.set_shader_parameter("morph_band_frac", 0.16)
	# grid_n drives the parent-ring UV snap for LOD morph (OA-C1).
	mat.set_shader_parameter("grid_n", float(grid_n))
	mat.set_shader_parameter("macro_aabb",
		Vector4(-1024.0, -1024.0, 1024.0, 1024.0))
	mat.set_shader_parameter("fallback_color",
		Color(0.35, 0.45, 0.25))
	# Layer 1 defaults: no array bound until bind_sibling_array() is
	# called. has_siblings=false routes the fragment shader through the
	# macro-only path (current Phase 4.6 behavior).
	mat.set_shader_parameter("sibling_start", 0)
	mat.set_shader_parameter("sibling_count", 0)
	mat.set_shader_parameter("has_siblings", false)
	mat.set_shader_parameter("sibling_tile_m", 8.0)
	mat.set_shader_parameter("sibling_normal_array", Texture2DArray.new())
	mat.set_shader_parameter("sibling_roughness_array", Texture2DArray.new())
	mat.set_shader_parameter("sibling_ao_array", Texture2DArray.new())
	mat.set_shader_parameter("has_sibling_normals", false)
	mat.set_shader_parameter("has_sibling_roughness", false)
	mat.set_shader_parameter("has_sibling_ao", false)
	# Layer 2 defaults: detail overlay disabled until bind_detail_array()
	mat.set_shader_parameter("detail_count", 0)
	mat.set_shader_parameter("has_detail", false)
	# Multi-page heightmap (Phase 4.9.a) defaults: not bound, legacy
	# height_map path active.
	mat.set_shader_parameter("has_height_array", false)
	mat.set_shader_parameter("height_pages_per_side", 1)
	mat.set_shader_parameter("height_array_min_xz", Vector2(0.0, 0.0))
	mat.set_shader_parameter("height_array_page_extent_m", 256.0)
	# Terrain-edge haze defaults: disabled until TerrainWorld binds the
	# tier-derived range after ring construction.
	mat.set_shader_parameter("terrain_haze_enabled", false)
	mat.set_shader_parameter("terrain_haze_start_m", 1000000.0)
	mat.set_shader_parameter("terrain_haze_end_m", 1000001.0)
	mat.set_shader_parameter("terrain_haze_strength", 0.0)
	mat.set_shader_parameter("terrain_haze_color",
		Color(0.646, 0.656, 0.674, 1.0))
	# Per-fragment slot selection (Phase 4.9.b): defaults to 0 slots
	# active. bind_all_slots() sets slot_count + the band arrays.
	mat.set_shader_parameter("slot_count", 0)
	# Pre-fill arrays with zeros so the shader's fixed-size uniforms
	# always exist (Godot rejects missing array uniforms at draw time).
	var zero_iv4: Array = []
	var zero_v4: Array = []
	for i in range(MAX_SLOTS):
		zero_iv4.append(Vector4i(0, 0, 0, 0))
		zero_v4.append(Vector4(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("slot_windows", zero_iv4)
	mat.set_shader_parameter("slot_elev_bands", zero_v4)
	mat.set_shader_parameter("slot_slope_bands", zero_v4)
	# Phase 6 biome_weights (5.7.b GDScript mirror): per-slot biome
	# index + per-biome auto_rule bands. Defaults to single-biome
	# (biome_count=0 → shader skips per-biome multiply).
	var zero_int: Array = []
	var zero_biome_v4: Array = []
	for i in range(MAX_SLOTS):
		zero_int.append(0)
	for i in range(MAX_BIOMES):
		zero_biome_v4.append(Vector4(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("slot_biome_index", zero_int)
	mat.set_shader_parameter("biome_count", 0)
	mat.set_shader_parameter("biome_auto_elev_bands", zero_biome_v4)
	mat.set_shader_parameter("biome_auto_slope_bands", zero_biome_v4)
	return mat


## Bind the heightmap texture + amplitude params for this ring.
##
## Legacy single-page path (Phase 4.4-4.8). Caller passes one Texture2D
## covering the ring's center page; outer rings stretch this at edges
## → chunk seams. Phase 4.9.a fix is bind_height_array (below).
func bind_height_map(mat: ShaderMaterial, height_tex: Texture2D,
		scale_m: float, offset_m: float) -> void:
	mat.set_shader_parameter("height_map", height_tex)
	mat.set_shader_parameter("height_scale", scale_m)
	mat.set_shader_parameter("height_offset", offset_m)


## Bind a multi-page heightmap Texture2DArray for the ring (Phase 4.9.a,
## audit C1 fix). Each layer holds one page; layer index = page_y *
## pages_per_side + page_x relative to `min_xz`. Vertex shader uses
## world XZ to pick the correct layer per fragment, eliminating the
## outer-ring chunk seams the legacy single-page binding produced.
##
## Caller passes:
##   array: Texture2DArray with pages_per_side² layers (RingHeightArray.build)
##   pages_per_side: width of the page grid (>= 1)
##   min_xz: world-space corner where page (0,0) starts
##   page_extent_m: width of one page in world meters
##   scale_m / offset_m: same amplitude/offset as bind_height_map
##
## Flips `has_height_array=true` so the vertex shader takes the array
## path. Call bind_height_map() with a single-page texture (or do
## nothing) to leave it false.
func bind_height_array(mat: ShaderMaterial, array: Texture2DArray,
		pages_per_side: int, min_xz: Vector2, page_extent_m: float,
		scale_m: float, offset_m: float) -> void:
	if array == null or pages_per_side <= 0:
		mat.set_shader_parameter("has_height_array", false)
		return
	mat.set_shader_parameter("height_array", array)
	mat.set_shader_parameter("has_height_array", true)
	mat.set_shader_parameter("height_pages_per_side", pages_per_side)
	mat.set_shader_parameter("height_array_min_xz", min_xz)
	mat.set_shader_parameter("height_array_page_extent_m", page_extent_m)
	mat.set_shader_parameter("height_scale", scale_m)
	mat.set_shader_parameter("height_offset", offset_m)


## Bind terrain-only distance haze. This is intentionally separate from
## the future Atmosphere controller; it gives the current clipmap a
## tier-driven fade band so the finite edge does not pop hard.
func bind_terrain_haze(mat: ShaderMaterial, enabled: bool,
		start_m: float, end_m: float, strength: float, color: Color) -> void:
	mat.set_shader_parameter("terrain_haze_enabled", enabled)
	mat.set_shader_parameter("terrain_haze_start_m", max(0.0, start_m))
	mat.set_shader_parameter("terrain_haze_end_m", max(end_m, start_m + 0.01))
	mat.set_shader_parameter("terrain_haze_strength",
		clamp(strength, 0.0, 1.0))
	mat.set_shader_parameter("terrain_haze_color", color)


## Bind the macro albedo texture + world-AABB so the fragment shader
## can do world-XZ → UV sampling.
func bind_macro_albedo(mat: ShaderMaterial, macro: MacroAlbedo) -> void:
	if macro == null:
		return
	if macro.texture != null:
		mat.set_shader_parameter("macro_albedo", macro.texture)
	mat.set_shader_parameter("macro_aabb", macro.uniform_aabb())


## Phase 4.10.a (W4 PITFALLS #11 fix). Bind per-ring morph geometry
## so the vertex shader can compute per-vertex morph factor from the
## vertex's distance to the ring's outer edge.
##
## - ring_center_xz: world XZ of the ring's current snapped center
## - half_extent_m: half the ring's world extent (ring covers
##   ±half_extent on each axis from center)
## - band_frac: fraction of half_extent that the morph band occupies
##   (0.16 = morph starts at 84% of the half-extent)
##
## Pass `ring_half_extent_m = 0.0` (or band_frac = 0.0) on the
## outermost ring — no parent to morph toward. The shader's morph
## becomes a no-op (m stays 0) so own-ring height renders directly.
func set_ring_morph(mat: ShaderMaterial, center_xz: Vector2,
		half_extent_m: float, band_frac: float = 0.16) -> void:
	mat.set_shader_parameter("ring_center_xz", center_xz)
	mat.set_shader_parameter("ring_half_extent_m", max(0.0, half_extent_m))
	mat.set_shader_parameter("morph_band_frac",
		clamp(band_frac, 0.0, 0.5))


## Legacy single-scalar morph setter. Phase 4.10.a deprecates this in
## favor of set_ring_morph(). Kept for the time being so any test or
## scene that still calls it doesn't crash; new code should use
## set_ring_morph().
func set_morph_factor(_mat: ShaderMaterial, _factor: float) -> void:
	# No-op: shader no longer reads `morph_factor` uniform. Per-vertex
	# morph computed from ring_center_xz + ring_half_extent_m + band.
	pass


## Bind a Texture2DArray of sibling textures + the start/count window
## the active slot's variants occupy. Flips has_siblings on so the
## fragment shader runs the Layer 1 3-tap blend instead of the macro-
## only path. count > SIBLING_COUNT_CAP is clamped (shader cap).
func bind_sibling_array(mat: ShaderMaterial, array: Texture2DArray,
		start_index: int, count: int) -> void:
	if array == null:
		return
	var clamped: int = min(count, SIBLING_COUNT_CAP)
	mat.set_shader_parameter("sibling_array", array)
	mat.set_shader_parameter("sibling_start", start_index)
	mat.set_shader_parameter("sibling_count", clamped)
	mat.set_shader_parameter("has_siblings", true)


## Bind the sibling_blend_freq uniform — controls the stochastic-UV
## noise wavelength for spec 24 Layer 1's 3-tap blend.
##
## Lower values = longer wavelength = same sibling reads further
## across the surface = visible tile repeat at eye height.
## Higher values = finer noise = siblings switch more often (audit C3).
##
## Per-tier in quality_tiers.json (terrain_sibling_blend_freq).
## Plumbed by TerrainWorld via QualityTiers.get_current().
##
## Negative or zero values are clamped to 0.01 (a small positive so
## the shader still produces some variation rather than freezing on
## a single sibling).
func bind_sibling_blend_freq(mat: ShaderMaterial, freq: float) -> void:
	var clamped: float = max(0.01, freq)
	mat.set_shader_parameter("sibling_blend_freq", clamped)


## Bind the world-space PBR tile size for sibling/slot textures.
##
## Per-tier in quality_tiers.json (terrain_pbr_tile_size_m). This feeds
## the shader's sibling_tile_m so authored quality tiers, not shader
## fallback defaults, control close-ground texture scale.
func bind_sibling_tile_size_m(mat: ShaderMaterial, tile_size_m: float) -> void:
	var clamped: float = max(0.01, tile_size_m)
	mat.set_shader_parameter("sibling_tile_m", clamped)


## Bind optional PBR maps that are layer-matched 1:1 with sibling_array.
## TerrainWorld validates layer/window alignment before calling this so
## shader layer indices can be reused safely for all maps.
func bind_sibling_pbr_arrays(mat: ShaderMaterial,
		normal_array: Texture2DArray,
		roughness_array: Texture2DArray,
		ao_array: Texture2DArray) -> void:
	var has_normals: bool = normal_array != null
	var has_roughness: bool = roughness_array != null
	var has_ao: bool = ao_array != null
	mat.set_shader_parameter("sibling_normal_array",
		normal_array if has_normals else Texture2DArray.new())
	mat.set_shader_parameter("sibling_roughness_array",
		roughness_array if has_roughness else Texture2DArray.new())
	mat.set_shader_parameter("sibling_ao_array",
		ao_array if has_ao else Texture2DArray.new())
	mat.set_shader_parameter("has_sibling_normals", has_normals)
	mat.set_shader_parameter("has_sibling_roughness", has_roughness)
	mat.set_shader_parameter("has_sibling_ao", has_ao)


## Bind a per-biome detail Texture2DArray with N overlay layers.
## Flips has_detail on so the fragment shader's Layer 2 blend runs.
## detail_count of 0 leaves the material unmodified (caller should
## just not bind in that case).
func bind_detail_array(mat: ShaderMaterial, array: Texture2DArray,
		count: int) -> void:
	if array == null or count <= 0:
		return
	mat.set_shader_parameter("detail_array", array)
	mat.set_shader_parameter("detail_count", count)
	mat.set_shader_parameter("has_detail", true)


## Bind ALL slots for per-fragment selection (Phase 4.9.b, spec 23
## hardened §"Surface slot model").
##
## - sibling_array: single Texture2DArray covering all slot variants
##   concatenated (SiblingTextureArray.build emits this)
## - windows: Array of {start: int, count: int} per slot, in slot order
## - elev_bands: Array of {min, max, band_min, band_max} per slot
##   (in meters). Smoothstep crossfade from min-band_min..min then
##   back down from max..max+band_max
## - slope_bands: Array of {min, max, band_min, band_max} per slot
##   (in degrees)
##
## Caller passes them in matched order; binder takes min(N, MAX_SLOTS).
## Empty inputs → has_siblings stays false (macro-only render path).
##
## Phase 6 (5.7.b GDScript Composer mirror): optional biome_indices
## tells the shader which biome each slot belongs to (so the per-
## fragment biome_weight from bind_biome_auto_rules multiplies the
## right slot's weight). Omit / empty array = all slots index biome 0
## (back-compat with single-biome scenes).
func bind_all_slots(mat: ShaderMaterial, sibling_array: Texture2DArray,
		windows: Array, elev_bands: Array, slope_bands: Array,
		biome_indices: Array = []) -> void:
	var n: int = min(min(windows.size(), elev_bands.size()),
		min(slope_bands.size(), MAX_SLOTS))
	if sibling_array == null or n == 0:
		mat.set_shader_parameter("slot_count", 0)
		mat.set_shader_parameter("has_siblings", false)
		return
	mat.set_shader_parameter("sibling_array", sibling_array)
	mat.set_shader_parameter("slot_count", n)
	mat.set_shader_parameter("has_siblings", true)
	# Pack windows as Vector4i (start, count, 0, 0); pad to MAX_SLOTS.
	var packed_windows: Array = []
	var packed_elev: Array = []
	var packed_slope: Array = []
	var packed_biome_idx: Array = []
	for i in range(MAX_SLOTS):
		if i < n:
			var w: Dictionary = windows[i]
			var e: Dictionary = elev_bands[i]
			var s: Dictionary = slope_bands[i]
			packed_windows.append(Vector4i(
				int(w.get("start", 0)),
				min(int(w.get("count", 0)), SIBLING_COUNT_CAP),
				0, 0))
			packed_elev.append(Vector4(
				float(e.get("min", -10000.0)),
				float(e.get("max",  10000.0)),
				float(e.get("band_min", 1.0)),
				float(e.get("band_max", 1.0))))
			packed_slope.append(Vector4(
				float(s.get("min", 0.0)),
				float(s.get("max", 90.0)),
				float(s.get("band_min", 1.0)),
				float(s.get("band_max", 1.0))))
			# Default to biome 0 when biome_indices is omitted/short.
			var bi: int = 0
			if i < biome_indices.size():
				bi = int(biome_indices[i])
			packed_biome_idx.append(clamp(bi, 0, MAX_BIOMES - 1))
		else:
			packed_windows.append(Vector4i(0, 0, 0, 0))
			packed_elev.append(Vector4(0.0, 0.0, 0.0, 0.0))
			packed_slope.append(Vector4(0.0, 0.0, 0.0, 0.0))
			packed_biome_idx.append(0)
	mat.set_shader_parameter("slot_windows", packed_windows)
	mat.set_shader_parameter("slot_elev_bands", packed_elev)
	mat.set_shader_parameter("slot_slope_bands", packed_slope)
	mat.set_shader_parameter("slot_biome_index", packed_biome_idx)


## Phase 6 (5.7.b GDScript Composer mirror). Bind per-biome
## auto_biome_rules so the fragment shader can compute
## biome_weight[i] = w5_band_weight(elev, slope, biome_auto_bands[i])
## per fragment + multiply each slot's weight by its biome_weight.
##
## - count: number of biomes (clamped to MAX_BIOMES=8)
## - elev_bands: Array of {min, max, band_min, band_max} per biome
##   (meters). Format matches bind_all_slots's per-slot elev_bands.
## - slope_bands: same shape (degrees)
##
## Pass count=0 to disable per-biome weighting (single-biome path;
## shader skips the multiply, all slots render at their slot_weight).
func bind_biome_auto_rules(mat: ShaderMaterial, count: int,
		elev_bands: Array, slope_bands: Array) -> void:
	var n: int = clamp(count, 0, MAX_BIOMES)
	mat.set_shader_parameter("biome_count", n)
	if n == 0:
		return
	var packed_elev: Array = []
	var packed_slope: Array = []
	for i in range(MAX_BIOMES):
		if i < n and i < elev_bands.size() and i < slope_bands.size():
			var e: Dictionary = elev_bands[i]
			var s: Dictionary = slope_bands[i]
			packed_elev.append(Vector4(
				float(e.get("min", -10000.0)),
				float(e.get("max",  10000.0)),
				float(e.get("band_min", 1.0)),
				float(e.get("band_max", 1.0))))
			packed_slope.append(Vector4(
				float(s.get("min", 0.0)),
				float(s.get("max", 90.0)),
				float(s.get("band_min", 1.0)),
				float(s.get("band_max", 1.0))))
		else:
			packed_elev.append(Vector4(0.0, 0.0, 0.0, 0.0))
			packed_slope.append(Vector4(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("biome_auto_elev_bands", packed_elev)
	mat.set_shader_parameter("biome_auto_slope_bands", packed_slope)


## Bind per-biome avg ground albedo. Used as a per-fragment biome-
## weighted fallback color in the shader (replaces the single global
## fallback_color) so coverage gaps blend to neighbor-biome ground
## color instead of olive green. colors is an Array of Color (or
## Vector3) in the same biome order as bind_biome_auto_rules.
##
## Pass an empty array to skip — shader keeps using single-biome
## fallback_color.
func bind_biome_fallback_colors(mat: ShaderMaterial, colors: Array) -> void:
	var packed: Array = []
	for i in range(MAX_BIOMES):
		if i < colors.size():
			var c = colors[i]
			if c is Color:
				packed.append(Vector3(c.r, c.g, c.b))
			else:
				packed.append(c as Vector3)
		else:
			packed.append(Vector3.ZERO)
	mat.set_shader_parameter("biome_fallback_colors", packed)


## Bind the Heitz-Neyret + region-based sampler uniforms (Phase 6 visual
## A/B 2026-05-17 follow-up). Replaces the in-fragment 3-tap stochastic
## blend with the combined region-pick + HN-tile path.
##
## - sibling_t_inv_array: layer-matched Texture2DArray of 256×1 inverse-
##   CDF LUTs (one per albedo). Pass null/empty to disable HN's variance-
##   preserving step (shader falls back to plain weighted blend within HN3).
## - region_size_m: world meters per region (e.g. 32-128). Manifest's
##   region_size_m.
## - edge_blend_m: crossfade band at region borders. Manifest's edge_blend_m.
## - world_seed: scene seed for region hashing. Manifest's world_seed.
func bind_variety_combined(mat: ShaderMaterial,
		sibling_t_inv_array: Texture2DArray,
		region_size_m: float, edge_blend_m: float,
		world_seed: int) -> void:
	var has_t_inv: bool = (sibling_t_inv_array != null)
	mat.set_shader_parameter("sibling_t_inv_array",
		sibling_t_inv_array if has_t_inv else Texture2DArray.new())
	mat.set_shader_parameter("has_t_inv", has_t_inv)
	mat.set_shader_parameter("region_size_m", max(region_size_m, 0.0))
	mat.set_shader_parameter("edge_blend_m", max(edge_blend_m, 0.0))
	mat.set_shader_parameter("world_seed", world_seed)
