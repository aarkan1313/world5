## Tests for DetailArray — per-biome detail overlay manifest loader/validator.
##
## Per spec 24 Layer 2. Loads detail_array.json which lists detail
## tile names + per-slot blend weights. Companion to MaterialVariants
## (Layer 1). Texture loading itself happens in DetailTextureArray
## (separate class); this just parses + validates the manifest.

extends GutTest


const FIXTURE_DIR := "user://_detail_array_fixture"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_DIR))


func _write(name: String, content: Dictionary) -> String:
	var path: String = "%s/%s.json" % [FIXTURE_DIR, name]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(content))
	f.close()
	return path


# --- load ---

func test_load_valid_manifest() -> void:
	var path: String = _write("valid", {
		"biome": "alpine",
		"detail_tiles": ["wet", "moss", "grunge"],
		"slot_blends": {
			"ground": {"wet": 0.6, "moss": 0.3, "grunge": 0.1},
			"mid":    {"wet": 0.2, "moss": 0.5, "grunge": 0.3},
			"rock":   {"wet": 0.1, "moss": 0.1, "grunge": 0.8},
		},
	})
	var da: DetailArray = DetailArray.from_file(path)
	assert_not_null(da)
	assert_eq(da.biome, "alpine")
	assert_eq(da.detail_tiles.size(), 3)
	assert_eq(da.tile_count(), 3)


func test_load_missing_file_returns_null() -> void:
	var da: DetailArray = DetailArray.from_file("user://does_not_exist.json")
	assert_null(da)


func test_load_real_walking_demo_manifest() -> void:
	# The checked-in scaffold manifest must load + validate (will be
	# "empty but valid" until Phase 5.4 wires real overlays).
	var da: DetailArray = DetailArray.from_file(
		"res://addons/world5/worlds/walking_demo/materials/biome_alpine/detail_array.json")
	assert_not_null(da, "walking_demo detail_array loads")
	var errors: Array = da.validate()
	assert_eq(errors.size(), 0,
		"walking_demo detail_array valid (errors: %s)" % str(errors))


# --- validation rules ---

func test_unknown_slot_blend_target_rejected() -> void:
	# A blend weight referencing a tile not in detail_tiles is broken
	# data — promote.py likely emitted a stale manifest.
	var path: String = _write("bad_tile_ref", {
		"biome": "alpine",
		"detail_tiles": ["wet"],
		"slot_blends": {
			"ground": {"wet": 0.5, "lichen": 0.3},
		},
	})
	var da: DetailArray = DetailArray.from_file(path)
	var errors: Array = da.validate()
	assert_gt(errors.size(), 0,
		"blend weight for unknown tile must error (got: %s)" % str(errors))


func test_weight_out_of_range_rejected() -> void:
	var path: String = _write("bad_weight", {
		"biome": "alpine",
		"detail_tiles": ["wet"],
		"slot_blends": {
			"ground": {"wet": 1.5},
		},
	})
	var da: DetailArray = DetailArray.from_file(path)
	var errors: Array = da.validate()
	assert_gt(errors.size(), 0, "weight > 1.0 must error")


func test_negative_weight_rejected() -> void:
	var path: String = _write("neg_weight", {
		"biome": "alpine",
		"detail_tiles": ["wet"],
		"slot_blends": {
			"ground": {"wet": -0.1},
		},
	})
	var da: DetailArray = DetailArray.from_file(path)
	var errors: Array = da.validate()
	assert_gt(errors.size(), 0, "negative weight must error")


# --- queries ---

func test_index_of_tile() -> void:
	var path: String = _write("indexable", {
		"biome": "x",
		"detail_tiles": ["a", "b", "c"],
		"slot_blends": {},
	})
	var da: DetailArray = DetailArray.from_file(path)
	assert_eq(da.index_of("a"), 0)
	assert_eq(da.index_of("c"), 2)
	assert_eq(da.index_of("missing"), -1)


func test_weights_for_slot() -> void:
	var path: String = _write("weighted", {
		"biome": "x",
		"detail_tiles": ["a", "b"],
		"slot_blends": {
			"ground": {"a": 0.4, "b": 0.6},
		},
	})
	var da: DetailArray = DetailArray.from_file(path)
	var weights: Dictionary = da.weights_for("ground")
	assert_eq(weights.size(), 2)
	assert_almost_eq(float(weights.get("a", 0.0)), 0.4, 1e-5)
	assert_almost_eq(float(weights.get("b", 0.0)), 0.6, 1e-5)
	# Unknown slot returns empty dict
	assert_eq(da.weights_for("missing").size(), 0)
