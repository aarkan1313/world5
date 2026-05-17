## Tests for MacroAlbedo — loads macro albedo texture + provides
## world-AABB → UV sampling uniforms.

extends GutTest


const FIXTURE_DIR := "user://_macro_albedo_fixture"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_DIR))


func test_constructible_with_defaults() -> void:
	var m: MacroAlbedo = MacroAlbedo.new()
	assert_null(m.texture)
	assert_eq(m.world_min_xz, Vector2.ZERO)
	assert_eq(m.world_max_xz, Vector2.ZERO)


# --- config loading ---

func test_load_config_sets_aabb() -> void:
	var config_path: String = "%s/macro_albedo.json" % FIXTURE_DIR
	var f: FileAccess = FileAccess.open(config_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"world_min_xz": [-1024.0, -1024.0],
		"world_max_xz": [1024.0, 1024.0],
		"texture": "res://addons/world5/icon.svg",  # any existing texture
	}))
	f.close()

	var m: MacroAlbedo = MacroAlbedo.new()
	assert_true(m.load_from_path(config_path))
	assert_eq(m.world_min_xz, Vector2(-1024.0, -1024.0))
	assert_eq(m.world_max_xz, Vector2(1024.0, 1024.0))


func test_load_missing_config_returns_false() -> void:
	var m: MacroAlbedo = MacroAlbedo.new()
	assert_false(m.load_from_path("res://does_not_exist.json"))


func test_load_missing_required_fields_returns_false() -> void:
	var path: String = "%s/incomplete.json" % FIXTURE_DIR
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"foo": "bar"}))
	f.close()
	var m: MacroAlbedo = MacroAlbedo.new()
	assert_false(m.load_from_path(path))


# --- world-to-UV mapping ---

func test_world_to_uv_at_min_corner() -> void:
	var m: MacroAlbedo = MacroAlbedo.new()
	m.world_min_xz = Vector2(-100.0, -100.0)
	m.world_max_xz = Vector2(100.0, 100.0)
	var uv: Vector2 = m.world_to_uv(Vector2(-100.0, -100.0))
	assert_almost_eq(uv.x, 0.0, 1e-5)
	assert_almost_eq(uv.y, 0.0, 1e-5)


func test_world_to_uv_at_max_corner() -> void:
	var m: MacroAlbedo = MacroAlbedo.new()
	m.world_min_xz = Vector2(-100.0, -100.0)
	m.world_max_xz = Vector2(100.0, 100.0)
	var uv: Vector2 = m.world_to_uv(Vector2(100.0, 100.0))
	assert_almost_eq(uv.x, 1.0, 1e-5)
	assert_almost_eq(uv.y, 1.0, 1e-5)


func test_world_to_uv_at_center() -> void:
	var m: MacroAlbedo = MacroAlbedo.new()
	m.world_min_xz = Vector2(-100.0, -100.0)
	m.world_max_xz = Vector2(100.0, 100.0)
	var uv: Vector2 = m.world_to_uv(Vector2.ZERO)
	assert_almost_eq(uv.x, 0.5, 1e-5)
	assert_almost_eq(uv.y, 0.5, 1e-5)


# --- shader uniforms ---

func test_uniform_aabb_packed_as_vec4() -> void:
	var m: MacroAlbedo = MacroAlbedo.new()
	m.world_min_xz = Vector2(-100.0, -50.0)
	m.world_max_xz = Vector2(100.0, 50.0)
	# vec4 (min_x, min_z, max_x, max_z) for one-sample shader fetch
	var uniform: Vector4 = m.uniform_aabb()
	assert_eq(uniform.x, -100.0)
	assert_eq(uniform.y, -50.0)
	assert_eq(uniform.z, 100.0)
	assert_eq(uniform.w, 50.0)
