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


# --- Phase 5.5: Layer 1 (siblings + stochastic UV) ---

func _make_sibling_array(layers: int, size: int = 4) -> Texture2DArray:
	## Build a Texture2DArray with N solid-color layers for tests.
	var imgs: Array = []
	for i in range(layers):
		var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		var c: float = float(i) / max(1.0, float(layers - 1))
		img.fill(Color(c, 1.0 - c, 0.5, 1.0))
		imgs.append(img)
	var arr: Texture2DArray = Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func test_bind_sibling_array_sets_texture_and_count() -> void:
	# Layer 1 contract: shader receives one Texture2DArray with all
	# sibling layers concatenated + per-slot (start, count) lookup so
	# the fragment shader's 3-tap sample knows which layers to blend.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_sibling_array(4)
	p.bind_sibling_array(mat, arr, 0, 4)
	assert_eq(mat.get_shader_parameter("sibling_array"), arr,
		"sibling_array uniform must hold the bound Texture2DArray")
	assert_eq(int(mat.get_shader_parameter("sibling_start")), 0)
	assert_eq(int(mat.get_shader_parameter("sibling_count")), 4)
	assert_eq((mat.get_shader_parameter("has_siblings") as bool), true,
		"has_siblings flag must flip true when array is bound")


func test_sibling_count_capped_at_8_per_spec_24() -> void:
	# Spec 24 max_variants_per_slot = 8 (shader limit). Binder must
	# enforce so callers don't silently overflow the shader's tap budget.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_sibling_array(12)
	p.bind_sibling_array(mat, arr, 0, 12)
	assert_lte(int(mat.get_shader_parameter("sibling_count")), 8,
		"binder must clamp sibling_count to shader cap of 8")


func test_unbinding_siblings_clears_has_flag() -> void:
	# Walking demo today has no real siblings yet; the path of "no
	# array bound" must keep has_siblings = false so the shader's
	# pre-Phase-5 macro-only path still works.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	# Default after make_ring_material: no array bound
	assert_eq((mat.get_shader_parameter("has_siblings") as bool), false,
		"has_siblings must default false on a fresh ring material")


# --- Phase 5.5: Layer 2 (detail overlays) ---

func _make_detail_array(layers: int, size: int = 4) -> Texture2DArray:
	## Like _make_sibling_array but builds detail overlay textures.
	var imgs: Array = []
	for i in range(layers):
		var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		# Alpha gradient per layer so each detail has a different
		# coverage profile (matches real overlay authoring shape)
		img.fill(Color(0.5, 0.5, 0.5, float(i + 1) / float(layers)))
		imgs.append(img)
	var arr: Texture2DArray = Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func test_bind_detail_array_sets_uniforms() -> void:
	# Layer 2 contract: one Texture2DArray of biome overlays + count
	# of layers + flag flips has_detail true so the shader runs the
	# detail blend; default-unbound preserves Phase 4.6 visual.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_detail_array(5)
	p.bind_detail_array(mat, arr, 5)
	assert_eq(mat.get_shader_parameter("detail_array"), arr)
	assert_eq(int(mat.get_shader_parameter("detail_count")), 5)
	assert_eq((mat.get_shader_parameter("has_detail") as bool), true)


func test_detail_unbound_flag_defaults_false() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	assert_eq((mat.get_shader_parameter("has_detail") as bool), false,
		"has_detail must default false on a fresh ring material")
