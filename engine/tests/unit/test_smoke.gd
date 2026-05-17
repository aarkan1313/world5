extends GutTest


func test_truthy() -> void:
	assert_true(true, "truth should hold")


func test_arithmetic() -> void:
	assert_eq(1 + 1, 2, "math works")


func test_godot_version() -> void:
	var version := Engine.get_version_info()
	assert_gte(version.major, 4, "Godot major version >= 4")
	if version.major == 4:
		assert_gte(version.minor, 5, "Godot 4.minor >= 5")
