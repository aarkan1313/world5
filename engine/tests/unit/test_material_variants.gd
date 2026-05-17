## Tests for MaterialVariants — sibling manifest loader/validator.
##
## Per spec 24 Layer 1 contract. Validates schema parsing + the
## W4-proven validation rules absorbed in 2026-05-17 spec amendment.

extends GutTest


const FIXTURE_DIR := "user://_material_variants_fixture"


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
		"world_seed": 42,
		"region_size_m": 512.0,
		"edge_blend_m": 48.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [
			{
				"biome": "alpine",
				"slot": "ground",
				"variants": [
					{"id": "default", "source": "ground", "weight": 1.0},
				],
			},
		],
	})
	var mv: MaterialVariants = MaterialVariants.from_file(path)
	assert_not_null(mv)
	assert_eq(mv.world_seed, 42)
	assert_eq(mv.region_size_m, 512.0)
	assert_eq(mv.slots.size(), 1)


func test_load_missing_file_returns_null() -> void:
	var mv: MaterialVariants = MaterialVariants.from_file("user://does_not_exist.json")
	assert_null(mv)


func test_load_real_walking_demo_manifest() -> void:
	# The actual checked-in manifest should load + validate
	var mv: MaterialVariants = MaterialVariants.from_file(
		"res://addons/world5/worlds/walking_demo/material_variants.json")
	assert_not_null(mv, "walking_demo manifest loads")
	var errors: Array = mv.validate()
	assert_eq(errors.size(), 0,
		"walking_demo manifest valid (errors: %s)" % str(errors))


# --- validation rules ---

func test_zero_region_size_rejected() -> void:
	var path: String = _write("bad_region", {
		"world_seed": 0,
		"region_size_m": 0.0,
		"edge_blend_m": 0.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [],
	})
	var mv: MaterialVariants = MaterialVariants.from_file(path)
	var errors: Array = mv.validate()
	assert_gt(errors.size(), 0)


func test_edge_blend_too_large_rejected() -> void:
	var path: String = _write("bad_blend", {
		"world_seed": 0,
		"region_size_m": 100.0,
		"edge_blend_m": 50.0,  # >= region_size_m / 4 = 25
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [],
	})
	var mv: MaterialVariants = MaterialVariants.from_file(path)
	var errors: Array = mv.validate()
	assert_gt(errors.size(), 0)


func test_variants_over_per_slot_cap_rejected() -> void:
	var variants: Array = []
	for i in range(12):
		variants.append({"id": "v%d" % i, "source": "s%d" % i, "weight": 1.0})
	var path: String = _write("too_many", {
		"world_seed": 0,
		"region_size_m": 512.0,
		"edge_blend_m": 48.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [{"biome": "x", "slot": "y", "variants": variants}],
	})
	var mv: MaterialVariants = MaterialVariants.from_file(path)
	var errors: Array = mv.validate()
	assert_gt(errors.size(), 0)


# --- queries ---

func test_variants_for_known() -> void:
	var path: String = _write("named", {
		"world_seed": 0,
		"region_size_m": 512.0,
		"edge_blend_m": 48.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [
			{
				"biome": "alpine",
				"slot": "ground",
				"variants": [
					{"id": "default", "source": "ground", "weight": 1.0},
					{"id": "v0", "source": "ground_variants/v0", "weight": 1.0},
				],
			},
		],
	})
	var mv: MaterialVariants = MaterialVariants.from_file(path)
	assert_eq(mv.variants_for("alpine", "ground").size(), 2)
	assert_eq(mv.variants_for("alpine", "missing").size(), 0)


func test_total_variant_layers_sums() -> void:
	var path: String = _write("totals", {
		"world_seed": 0,
		"region_size_m": 512.0,
		"edge_blend_m": 48.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [
			{"biome": "a", "slot": "g", "variants": [{},{},{}]},
			{"biome": "a", "slot": "m", "variants": [{},{}]},
		],
	})
	var mv: MaterialVariants = MaterialVariants.from_file(path)
	assert_eq(mv.total_variant_layers(), 5)
