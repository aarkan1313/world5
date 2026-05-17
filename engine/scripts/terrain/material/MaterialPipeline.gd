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
