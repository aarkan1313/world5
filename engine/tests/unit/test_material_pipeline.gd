## Tests for MaterialPipeline — owns the per-ring ShaderMaterial +
## binds heightmap / macro / morph uniforms.
##
## Headless-safe: tests ShaderMaterial creation + uniform set/get.
## Actual shader compile lives in a real-device integration test.

extends GutTest


func test_constructible() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	assert_not_null(p)


func test_make_ring_material_returns_shader_material() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	assert_not_null(mat)
	assert_not_null(mat.shader)


func test_set_macro_albedo_uniform() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var macro: MacroAlbedo = MacroAlbedo.new()
	macro.world_min_xz = Vector2(-512.0, -512.0)
	macro.world_max_xz = Vector2(512.0, 512.0)
	p.bind_macro_albedo(mat, macro)
	var aabb: Vector4 = mat.get_shader_parameter("macro_aabb")
	assert_almost_eq(aabb.x, -512.0, 1e-5)
	assert_almost_eq(aabb.z, 512.0, 1e-5)


func test_set_morph_factor() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.set_morph_factor(mat, 0.75)
	assert_almost_eq(float(mat.get_shader_parameter("morph_factor")), 0.75, 1e-5)


func test_bind_height_texture() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	# Use a simple ImageTexture as the height map
	var img: Image = Image.create(8, 8, false, Image.FORMAT_RF)
	img.fill(Color(0.5, 0, 0, 0))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	p.bind_height_map(mat, tex, 50.0, 0.0)
	assert_eq(mat.get_shader_parameter("height_map"), tex)
	assert_almost_eq(float(mat.get_shader_parameter("height_scale")),
		50.0, 1e-5)


func test_shader_consumes_morph_factor() -> void:
	# OA-C1 audit fix: morph_factor was declared as a uniform but
	# never sampled in the shader body — declared-but-unused. This
	# test guards against regression by asserting the shader source
	# actually references morph_factor in vertex() (not just declares
	# it). Pure text check; doesn't need GPU.
	var f: FileAccess = FileAccess.open(
		"res://addons/world5/shaders/terrain_clipmap.gdshader",
		FileAccess.READ)
	assert_not_null(f, "shader file readable")
	var src: String = f.get_as_text()
	f.close()
	# Count references — declaration is one, body uses must be > 0.
	var count: int = src.count("morph_factor")
	assert_gt(count, 1,
		"morph_factor must be USED in shader body, not just declared (saw %d ref(s))" % count)


func test_shader_consumes_grid_n_for_morph() -> void:
	# OA-C1 follow-up: grid_n uniform drives parent-ring UV snap that
	# the morph blend samples. Same regression-guard pattern.
	var f: FileAccess = FileAccess.open(
		"res://addons/world5/shaders/terrain_clipmap.gdshader",
		FileAccess.READ)
	var src: String = f.get_as_text()
	f.close()
	assert_gt(src.count("grid_n"), 1,
		"grid_n must be USED in shader body for parent-ring UV snap")


func test_per_ring_materials_are_independent() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var m0: ShaderMaterial = p.make_ring_material(0)
	var m1: ShaderMaterial = p.make_ring_material(1)
	p.set_morph_factor(m0, 0.2)
	p.set_morph_factor(m1, 0.8)
	assert_almost_eq(float(m0.get_shader_parameter("morph_factor")), 0.2, 1e-5)
	assert_almost_eq(float(m1.get_shader_parameter("morph_factor")), 0.8, 1e-5)
