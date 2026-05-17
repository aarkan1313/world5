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
	mat.set_shader_parameter("morph_factor", 0.0)
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
	# Layer 2 defaults: detail overlay disabled until bind_detail_array()
	mat.set_shader_parameter("detail_count", 0)
	mat.set_shader_parameter("has_detail", false)
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
	return mat


## Bind the heightmap texture + amplitude params for this ring.
func bind_height_map(mat: ShaderMaterial, height_tex: Texture2D,
		scale_m: float, offset_m: float) -> void:
	mat.set_shader_parameter("height_map", height_tex)
	mat.set_shader_parameter("height_scale", scale_m)
	mat.set_shader_parameter("height_offset", offset_m)


## Bind the macro albedo texture + world-AABB so the fragment shader
## can do world-XZ → UV sampling.
func bind_macro_albedo(mat: ShaderMaterial, macro: MacroAlbedo) -> void:
	if macro == null:
		return
	if macro.texture != null:
		mat.set_shader_parameter("macro_albedo", macro.texture)
	mat.set_shader_parameter("macro_aabb", macro.uniform_aabb())


## Set the LOD-morph factor (0 = current LOD, 1 = morphed to next).
func set_morph_factor(mat: ShaderMaterial, factor: float) -> void:
	mat.set_shader_parameter("morph_factor", clamp(factor, 0.0, 1.0))


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
func bind_all_slots(mat: ShaderMaterial, sibling_array: Texture2DArray,
		windows: Array, elev_bands: Array, slope_bands: Array) -> void:
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
		else:
			packed_windows.append(Vector4i(0, 0, 0, 0))
			packed_elev.append(Vector4(0.0, 0.0, 0.0, 0.0))
			packed_slope.append(Vector4(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("slot_windows", packed_windows)
	mat.set_shader_parameter("slot_elev_bands", packed_elev)
	mat.set_shader_parameter("slot_slope_bands", packed_slope)
