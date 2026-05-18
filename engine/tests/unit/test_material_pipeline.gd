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


# --- Phase 4.9.b: per-fragment slot selection ---

func test_bind_all_slots_sets_slot_count_and_windows() -> void:
	# Spec 23 hardened contract: every slot's sibling window MUST be
	# bound, not just the first. Previously TerrainWorld bound only
	# mv.slots[0] making mid + rock dead weight.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_sibling_array(9)  # 3 slots * 3 variants
	var windows: Array = [
		{"start": 0, "count": 3},
		{"start": 3, "count": 3},
		{"start": 6, "count": 3},
	]
	var elev_bands: Array = [
		{"min": -50.0, "max": 5.0, "band_min": 8.0, "band_max": 8.0},
		{"min": -15.0, "max": 30.0, "band_min": 10.0, "band_max": 10.0},
		{"min": 10.0, "max": 50.0, "band_min": 12.0, "band_max": 12.0},
	]
	var slope_bands: Array = [
		{"min": 0.0, "max": 20.0, "band_min": 5.0, "band_max": 5.0},
		{"min": 10.0, "max": 45.0, "band_min": 8.0, "band_max": 8.0},
		{"min": 30.0, "max": 90.0, "band_min": 10.0, "band_max": 10.0},
	]
	p.bind_all_slots(mat, arr, windows, elev_bands, slope_bands)
	assert_eq(mat.get_shader_parameter("sibling_array"), arr)
	assert_eq(int(mat.get_shader_parameter("slot_count")), 3)
	# slot_windows packed as ivec4[8]; first 3 entries non-zero
	# (xy = start,count; zw unused)
	var w: Array = mat.get_shader_parameter("slot_windows")
	assert_not_null(w, "slot_windows uniform must be set")
	assert_gte(w.size(), 3,
		"slot_windows must have at least slot_count entries (got %d)" % w.size())
	# has_siblings flips true since at least one window is non-empty
	assert_eq((mat.get_shader_parameter("has_siblings") as bool), true)


func test_bind_all_slots_caps_at_max_slots() -> void:
	# Spec 23 hard cap is 8 slots per biome (shader limit). Caller
	# passing more must be clamped at the binder so the shader's
	# fixed-size arrays don't overflow.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_sibling_array(20)
	var windows: Array = []
	var elev_bands: Array = []
	var slope_bands: Array = []
	for i in range(12):  # over the 8-slot cap
		windows.append({"start": i * 2, "count": 2})
		elev_bands.append({"min": 0.0, "max": 50.0, "band_min": 5.0, "band_max": 5.0})
		slope_bands.append({"min": 0.0, "max": 45.0, "band_min": 5.0, "band_max": 5.0})
	p.bind_all_slots(mat, arr, windows, elev_bands, slope_bands)
	assert_lte(int(mat.get_shader_parameter("slot_count")), 8,
		"slot_count must clamp to MAX_SLOTS=8 (spec 23 hard cap)")


func test_bind_all_slots_empty_windows_leaves_has_siblings_false() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.bind_all_slots(mat, null, [], [], [])
	assert_eq((mat.get_shader_parameter("has_siblings") as bool), false,
		"empty/null inputs must leave has_siblings false (macro-only path)")


func test_bind_sibling_blend_freq_sets_uniform() -> void:
	# Phase 5.4.b audit C3 fix. sibling_blend_freq drives the
	# stochastic-UV noise wavelength; per-tier so high tiers can
	# afford finer-frequency variation (less visible tile repeat).
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.bind_sibling_blend_freq(mat, 0.35)
	assert_almost_eq(float(mat.get_shader_parameter("sibling_blend_freq")),
		0.35, 0.001, "binder must set the uniform exactly as passed")


func test_bind_sibling_blend_freq_clamps_negative() -> void:
	# Negative or zero frequency is nonsensical (would freeze noise
	# at a single sibling). Binder must clamp to a small positive.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.bind_sibling_blend_freq(mat, -0.5)
	assert_gt(float(mat.get_shader_parameter("sibling_blend_freq")), 0.0,
		"negative freq must be clamped to a small positive")
	assert_eq(int(mat.get_shader_parameter("slot_count")), 0)


func test_bind_sibling_tile_size_m_sets_uniform() -> void:
	# terrain_pbr_tile_size_m from quality_tiers.json must reach the
	# shader's sibling_tile_m uniform; shader defaults are only fallback.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.bind_sibling_tile_size_m(mat, 12.5)
	assert_almost_eq(float(mat.get_shader_parameter("sibling_tile_m")),
		12.5, 0.001, "binder must set PBR tile size exactly as passed")


func test_bind_sibling_tile_size_m_clamps_nonpositive() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.bind_sibling_tile_size_m(mat, 0.0)
	assert_gt(float(mat.get_shader_parameter("sibling_tile_m")), 0.0,
		"nonpositive tile size must be clamped to a small positive")


func test_bind_sibling_pbr_arrays_sets_uniforms() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var normal_arr: Texture2DArray = _make_sibling_array(3)
	var roughness_arr: Texture2DArray = _make_sibling_array(3)
	var ao_arr: Texture2DArray = _make_sibling_array(3)
	p.bind_sibling_pbr_arrays(mat, normal_arr, roughness_arr, ao_arr)
	assert_eq(mat.get_shader_parameter("sibling_normal_array"), normal_arr,
		"normal PBR array must be bound")
	assert_eq(mat.get_shader_parameter("sibling_roughness_array"), roughness_arr,
		"roughness PBR array must be bound")
	assert_eq(mat.get_shader_parameter("sibling_ao_array"), ao_arr,
		"AO PBR array must be bound")
	assert_eq((mat.get_shader_parameter("has_sibling_normals") as bool), true)
	assert_eq((mat.get_shader_parameter("has_sibling_roughness") as bool), true)
	assert_eq((mat.get_shader_parameter("has_sibling_ao") as bool), true)


func test_bind_sibling_pbr_arrays_allows_partial_maps() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var roughness_arr: Texture2DArray = _make_sibling_array(3)
	p.bind_sibling_pbr_arrays(mat, null, roughness_arr, null)
	assert_eq((mat.get_shader_parameter("has_sibling_normals") as bool), false)
	assert_eq((mat.get_shader_parameter("has_sibling_roughness") as bool), true)
	assert_eq((mat.get_shader_parameter("has_sibling_ao") as bool), false)
	assert_true(mat.get_shader_parameter("sibling_roughness_array") is Texture2DArray)


# --- Phase 6 biome_weights (5.7.b GDScript runtime mirror) ---


func test_bind_biome_auto_rules_sets_uniforms() -> void:
	# Per spec 22 §Catalog schema, each biome has auto_biome_rules
	# (elevation_m + slope_deg bands). At runtime the fragment shader
	# computes biome_weight per fragment from these bands; this binder
	# packs them into the shader's fixed-size uniform arrays.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var elev_bands: Array = [
		{"min": -50.0, "max": 10.0, "band_min": 10.0, "band_max": 10.0},
		{"min":  10.0, "max": 60.0, "band_min": 10.0, "band_max": 10.0},
	]
	var slope_bands: Array = [
		{"min": 0.0, "max": 90.0, "band_min": 5.0, "band_max": 5.0},
		{"min": 0.0, "max": 90.0, "band_min": 5.0, "band_max": 5.0},
	]
	p.bind_biome_auto_rules(mat, 2, elev_bands, slope_bands)
	assert_eq(int(mat.get_shader_parameter("biome_count")), 2,
		"biome_count uniform must reflect the bound count")
	var packed_elev: Array = mat.get_shader_parameter("biome_auto_elev_bands") as Array
	assert_eq(packed_elev.size(), 8,
		"biome_auto_elev_bands must be padded to MAX_BIOMES (8)")
	var first: Vector4 = packed_elev[0] as Vector4
	assert_almost_eq(first.x, -50.0, 0.001, "elev band 0 min packed")
	assert_almost_eq(first.y,  10.0, 0.001, "elev band 0 max packed")


func test_bind_biome_auto_rules_caps_at_max_biomes() -> void:
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var elev_bands: Array = []
	var slope_bands: Array = []
	for i in range(12):  # over the 8-biome cap
		elev_bands.append({"min": 0.0, "max": 50.0,
			"band_min": 5.0, "band_max": 5.0})
		slope_bands.append({"min": 0.0, "max": 45.0,
			"band_min": 5.0, "band_max": 5.0})
	p.bind_biome_auto_rules(mat, 12, elev_bands, slope_bands)
	assert_lte(int(mat.get_shader_parameter("biome_count")), 8,
		"biome_count must clamp to MAX_BIOMES=8 hard cap")


func test_bind_biome_auto_rules_zero_count_disables() -> void:
	# Single-biome scenes don't need biome weighting; pass count=0
	# and the shader skips the per-biome multiply.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.bind_biome_auto_rules(mat, 0, [], [])
	assert_eq(int(mat.get_shader_parameter("biome_count")), 0,
		"biome_count=0 routes shader through legacy single-biome path")


func test_bind_all_slots_accepts_biome_indices() -> void:
	# Phase 6 unblock: bind_all_slots now accepts an optional biome_indices
	# array. Each slot's biome_index tells the shader which biome_weight
	# to multiply by. Missing array → all slots index biome 0 (back-compat
	# with single-biome scenes).
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_sibling_array(6)
	var windows: Array = [
		{"start": 0, "count": 3}, {"start": 3, "count": 3},
	]
	var elev_bands: Array = [
		{"min": -50.0, "max": 15.0, "band_min": 5.0, "band_max": 5.0},
		{"min":  -5.0, "max": 35.0, "band_min": 5.0, "band_max": 5.0},
	]
	var slope_bands: Array = [
		{"min": 0.0, "max": 25.0, "band_min": 3.0, "band_max": 3.0},
		{"min": 0.0, "max": 25.0, "band_min": 3.0, "band_max": 3.0},
	]
	var biome_indices: Array = [0, 1]  # slot 0 -> biome 0, slot 1 -> biome 1
	p.bind_all_slots(mat, arr, windows, elev_bands, slope_bands,
		biome_indices)
	var packed: Array = mat.get_shader_parameter("slot_biome_index") as Array
	assert_eq(int(packed[0]), 0, "slot 0 indexed to biome 0")
	assert_eq(int(packed[1]), 1, "slot 1 indexed to biome 1")


func test_bind_all_slots_back_compat_no_biome_indices() -> void:
	# When biome_indices is omitted, all slots default to biome 0.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_sibling_array(3)
	var windows: Array = [{"start": 0, "count": 3}]
	var elev_bands: Array = [
		{"min": -50.0, "max": 15.0, "band_min": 5.0, "band_max": 5.0}]
	var slope_bands: Array = [
		{"min": 0.0, "max": 25.0, "band_min": 3.0, "band_max": 3.0}]
	p.bind_all_slots(mat, arr, windows, elev_bands, slope_bands)
	var packed: Array = mat.get_shader_parameter("slot_biome_index") as Array
	assert_eq(int(packed[0]), 0,
		"omitted biome_indices defaults all slots to biome 0")
