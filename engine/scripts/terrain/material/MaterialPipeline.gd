## MaterialPipeline — owns the per-ring ShaderMaterial + binds
## heightmap, macro albedo, ring uniforms.
##
## Per spec 21 module decomposition + spec 24 layers. Phase 4 ships:
##   - heightmap per-ring (Texture2D bound; Phase 4.6 will swap to
##     Texture2DRD when renderer consumes GPU pages directly)
##   - macro albedo (one world-spanning texture)
##   - morph factor uniform (ClipmapDispatch computes; this binds)
##
## Sibling/detail array integration deferred until the texture
## pipeline (Phase 5) produces those assets.

class_name MaterialPipeline extends RefCounted


const SHADER_PATH := "res://addons/world5/shaders/terrain_clipmap.gdshader"


# Lazily-loaded Shader resource shared across all ring materials
var _shader: Shader = null


## Construct a fresh ShaderMaterial for the given ring index.
## Independent materials per ring so each can hold its own morph
## factor + heightmap (Phase 4.4.d composer wires them).
func make_ring_material(_ring_index: int) -> ShaderMaterial:
	if _shader == null:
		_shader = load(SHADER_PATH)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _shader
	# Sensible defaults so the material renders SOMETHING even before
	# the composer binds real assets
	mat.set_shader_parameter("height_scale", 50.0)
	mat.set_shader_parameter("height_offset", 0.0)
	mat.set_shader_parameter("morph_factor", 0.0)
	mat.set_shader_parameter("macro_aabb",
		Vector4(-1024.0, -1024.0, 1024.0, 1024.0))
	mat.set_shader_parameter("fallback_color",
		Color(0.35, 0.45, 0.25))
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
