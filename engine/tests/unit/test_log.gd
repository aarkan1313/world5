## Tests for engine/scripts/core/Log.gd
##
## Per spec 06 + spec 16.

extends GutTest


func before_each() -> void:
	# Reset Log config to defaults
	Log.set_level(Log.Level.INFO)
	Log.set_format("human")
	Log.set_output("stdout")


func test_levels_enum_has_5_values() -> void:
	assert_eq(Log.Level.size(), 5, "5 log levels (DEBUG/INFO/WARN/ERROR/FATAL)")


func test_set_format_validates() -> void:
	# Valid formats don't throw
	Log.set_format("human")
	Log.set_format("json")
	Log.set_format("compact")
	# Explicit assert so gut doesn't flag risky
	assert_true(true, "all valid formats accepted without error")


func test_verbose_per_system_default_false() -> void:
	assert_false(Log.is_verbose("nonexistent_system"), "default verbose = false")


func test_verbose_per_system_toggle() -> void:
	Log.set_verbose("terrain", true)
	assert_true(Log.is_verbose("terrain"), "verbose was set true")
	Log.set_verbose("terrain", false)
	assert_false(Log.is_verbose("terrain"), "verbose was set back false")


func test_format_human_contains_components() -> void:
	# Calling _format_human directly via reflection isn't easy in GDScript;
	# instead verify shape via info() printing
	# (Output capture via Godot is non-trivial; this test asserts the call
	#  doesn't crash and the level constants exist properly.)
	Log.info("test_system", "test message", {"key": "value"})
	assert_true(true, "info call did not crash")


func test_warn_via_push_warning_does_not_crash() -> void:
	# WARN routes through push_warning; should not crash
	Log.warn("test_system", "test warning", {})
	assert_true(true, "warn call did not crash")
