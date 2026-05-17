## Tests for variety_common.gdshaderinc primitives.
##
## Text-level assertions only; actual shader behavior validated in
## the real-GPU visual test (test_terrain_capture_baseline_real_device
## + Phase 5.5 visual capture).

extends GutTest


const SHADER_INC := "res://addons/world5/shaders/variety_common.gdshaderinc"


func _read() -> String:
	var f: FileAccess = FileAccess.open(SHADER_INC, FileAccess.READ)
	assert_not_null(f, "variety_common.gdshaderinc readable")
	var src: String = f.get_as_text()
	f.close()
	return src


# --- Phase 4 primitives (already shipped) ---

func test_world_noise_exists() -> void:
	assert_true(_read().contains("w5_world_noise"),
		"w5_world_noise primitive must exist for Layer 3 macro modulation")


func test_macro_uv_exists() -> void:
	assert_true(_read().contains("w5_macro_uv"),
		"w5_macro_uv primitive must exist for Layer 3 macro sampling")


# --- Phase 5.5 Layer 1 primitive ---

func test_variety_sample_3tap_exists() -> void:
	# Heitz-Neyret 2018 simplified 3-tap stochastic UV blend. Spec 24
	# Layer 1. Must be defined as a function in the .gdshaderinc so
	# terrain_clipmap.gdshader can include + call it.
	var src: String = _read()
	assert_true(src.contains("w5_variety_sample_3tap"),
		"w5_variety_sample_3tap primitive required for Layer 1")
	# Sanity: it must be a function definition (returns vec4 albedo+a),
	# not just a comment mentioning the name.
	assert_true(src.contains("vec4 w5_variety_sample_3tap"),
		"w5_variety_sample_3tap must be declared as a function returning vec4")


func test_variety_sample_3tap_takes_sampler2darray() -> void:
	# The whole point of Layer 1 is sampling from a Texture2DArray
	# (siblings). If the primitive doesn't take a sampler2DArray its
	# signature is wrong.
	var src: String = _read()
	assert_true(src.contains("sampler2DArray"),
		"3-tap sample primitive must take a sampler2DArray (siblings)")


func test_terrain_shader_calls_variety_sample_3tap() -> void:
	# The fragment shader must actually USE the new primitive when
	# has_siblings flag is true — declared-but-unused would be a
	# regression (mirrors test_shader_consumes_morph_factor).
	var f: FileAccess = FileAccess.open(
		"res://addons/world5/shaders/terrain_clipmap.gdshader",
		FileAccess.READ)
	assert_not_null(f)
	var src: String = f.get_as_text()
	f.close()
	assert_true(src.contains("w5_variety_sample_3tap"),
		"terrain_clipmap.gdshader must call w5_variety_sample_3tap")
	assert_true(src.contains("has_siblings"),
		"terrain_clipmap.gdshader must branch on has_siblings flag")


# --- Phase 5.5 Layer 2 primitive ---

func test_detail_blend_exists() -> void:
	# Spec 24 Layer 2: per-biome detail overlay blend. Pure-shader
	# function in variety_common so terrain (and later water/decoration
	# specs) can call it.
	var src: String = _read()
	assert_true(src.contains("w5_detail_blend"),
		"w5_detail_blend primitive required for Layer 2")
	assert_true(src.contains("vec4 w5_detail_blend"),
		"w5_detail_blend must be declared as a function returning vec4")


func test_terrain_shader_calls_detail_blend() -> void:
	var f: FileAccess = FileAccess.open(
		"res://addons/world5/shaders/terrain_clipmap.gdshader",
		FileAccess.READ)
	var src: String = f.get_as_text()
	f.close()
	assert_true(src.contains("w5_detail_blend"),
		"terrain_clipmap.gdshader must call w5_detail_blend")
	assert_true(src.contains("has_detail"),
		"terrain_clipmap.gdshader must branch on has_detail flag")


# --- Phase 4.9.b: per-fragment slot selection ---

func test_slot_weight_primitive_exists() -> void:
	# Per spec 23 §"Surface slot model" hardened in audit C2.
	# w5_slot_weight(slot_idx, elev_m, slope_deg) returns the
	# smoothstep-banded weight for one slot.
	var src: String = _read()
	assert_true(src.contains("w5_slot_weight"),
		"w5_slot_weight primitive required for per-fragment slot selection")
	assert_true(src.contains("float w5_slot_weight"),
		"w5_slot_weight must be declared as float-returning function")


func test_terrain_shader_loops_over_slots() -> void:
	# Fragment shader must loop over slot_count, calling w5_slot_weight
	# for each + w5_variety_sample_3tap for the matching window,
	# accumulating a weighted average.
	var f: FileAccess = FileAccess.open(
		"res://addons/world5/shaders/terrain_clipmap.gdshader",
		FileAccess.READ)
	var src: String = f.get_as_text()
	f.close()
	assert_true(src.contains("slot_count"),
		"shader must read slot_count uniform")
	assert_true(src.contains("w5_slot_weight"),
		"shader must call w5_slot_weight in fragment loop")
	assert_true(src.contains("slot_windows"),
		"shader must read slot_windows uniform")


func test_vertex_derives_slope_from_heightmap() -> void:
	# Per-fragment slot selection needs slope_deg per fragment. The
	# vertex shader computes it from heightmap finite differences
	# (sample +/-eps in U and V) and passes via varying.
	var f: FileAccess = FileAccess.open(
		"res://addons/world5/shaders/terrain_clipmap.gdshader",
		FileAccess.READ)
	var src: String = f.get_as_text()
	f.close()
	assert_true(src.contains("v_slope_deg") or src.contains("v_world_y"),
		"vertex must publish slope (v_slope_deg) or world Y (v_world_y) " +
		"for per-fragment slot selection")
