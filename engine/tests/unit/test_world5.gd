## Tests for engine/scripts/core/World5.gd version helpers.
##
## Per spec 17.

extends GutTest


func test_version_string_set() -> void:
	assert_eq(World5.VERSION, "0.0.1", "Phase 0 ships version 0.0.1")


func test_parse_valid_semver() -> void:
	assert_eq(World5.parse("1.2.3"), [1, 2, 3])
	assert_eq(World5.parse("0.1.0"), [0, 1, 0])


func test_parse_strips_prerelease() -> void:
	assert_eq(World5.parse("0.1.0-beta.1"), [0, 1, 0])


func test_parse_invalid_returns_zeros() -> void:
	assert_eq(World5.parse("not.a.version"), [0, 0, 0])
	assert_eq(World5.parse("1.2"), [0, 0, 0])


func test_is_compatible_same_version() -> void:
	# Runtime is 0.0.1 per VERSION constant
	assert_true(World5.is_compatible("0.0.1"))


func test_is_compatible_pre_1_0_minor_breaks() -> void:
	# Runtime is 0.0.x; an artifact at 0.1.0 is NOT compat
	assert_false(World5.is_compatible("0.1.0"))


func test_needs_migration_inverse() -> void:
	assert_false(World5.needs_migration("0.0.1"))
	assert_true(World5.needs_migration("0.1.0"))
	assert_true(World5.needs_migration("1.0.0"))


func test_migration_path_same_empty() -> void:
	assert_eq(World5.migration_path("0.1.0", "0.1.0"), [])


func test_migration_path_direct_stub() -> void:
	assert_eq(World5.migration_path("0.1.0", "0.4.0"), ["0.4.0"])
