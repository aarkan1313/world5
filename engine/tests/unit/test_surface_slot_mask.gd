## Tests for SurfaceSlotMask — loads surface_slots.json + maps slot
## names to indices for shader binding.

extends GutTest


const FIXTURE_DIR := "user://_surface_slot_fixture"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_DIR))


func _write_fixture(name: String, content: Dictionary) -> String:
	var path: String = "%s/%s.json" % [FIXTURE_DIR, name]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(content))
	f.close()
	return path


# --- load ---

func test_load_valid_file() -> void:
	var path: String = _write_fixture("valid", {
		"slots": [
			{"name": "grass", "siblings": ["res://grass_a.png"]},
			{"name": "rock", "siblings": ["res://rock_a.png"]},
		],
	})
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	assert_true(mask.load_from_path(path))
	assert_eq(mask.slot_count(), 2)


func test_load_missing_file_returns_false() -> void:
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	assert_false(mask.load_from_path("res://does_not_exist.json"))
	assert_eq(mask.slot_count(), 0)


func test_load_malformed_json_returns_false() -> void:
	var path: String = "%s/malformed.json" % FIXTURE_DIR
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not valid json")
	f.close()
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	assert_false(mask.load_from_path(path))


func test_load_missing_slots_key_returns_false() -> void:
	var path: String = _write_fixture("no_slots", {"foo": "bar"})
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	assert_false(mask.load_from_path(path))


# --- index lookup ---

func test_index_of_known_slot() -> void:
	var path: String = _write_fixture("named", {
		"slots": [
			{"name": "grass", "siblings": []},
			{"name": "rock", "siblings": []},
			{"name": "snow", "siblings": []},
		],
	})
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	mask.load_from_path(path)
	assert_eq(mask.index_of("grass"), 0)
	assert_eq(mask.index_of("rock"), 1)
	assert_eq(mask.index_of("snow"), 2)


func test_index_of_unknown_returns_neg_one() -> void:
	var path: String = _write_fixture("known_only", {
		"slots": [{"name": "grass", "siblings": []}],
	})
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	mask.load_from_path(path)
	assert_eq(mask.index_of("missing"), -1)


# --- sibling textures ---

func test_siblings_for_slot() -> void:
	var path: String = _write_fixture("with_siblings", {
		"slots": [
			{"name": "grass", "siblings": [
				"res://g_a.png", "res://g_b.png", "res://g_c.png",
			]},
		],
	})
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	mask.load_from_path(path)
	var siblings: Array = mask.siblings_for(0)
	assert_eq(siblings.size(), 3)
	assert_eq(siblings[0], "res://g_a.png")


# --- validate ---

func test_validate_empty_slots_errors() -> void:
	var path: String = _write_fixture("empty_slots", {"slots": []})
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	mask.load_from_path(path)
	assert_gt(mask.validate().size(), 0)


func test_validate_no_siblings_errors() -> void:
	var path: String = _write_fixture("no_sibs", {
		"slots": [{"name": "grass", "siblings": []}],
	})
	var mask: SurfaceSlotMask = SurfaceSlotMask.new()
	mask.load_from_path(path)
	# At least one sibling required per slot (variety architecture
	# needs ≥ 1 to sample anything)
	var errors: Array = mask.validate()
	assert_gt(errors.size(), 0)
