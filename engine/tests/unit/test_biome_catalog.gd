## Tests for BiomeCatalog — per-world biome manifest loader (spec 22).
##
## Per-biome surface slot selectors drive the per-fragment slot weight
## computation in the terrain shader (spec 23 §Surface slot model,
## hardened in audit C2 2026-05-17 + Phase 4.9.b).

extends GutTest


const FIXTURE_DIR := "user://_biome_catalog_fixture"


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

func test_load_valid_catalog() -> void:
	var path: String = _write("valid", {
		"world_name": "test",
		"biome_scale_m": 1024.0,
		"elevation_range_m": [-50.0, 50.0],
		"biomes": [{
			"name": "alpine",
			"kernel": {"type": "noise_stack", "params": {}},
			"material_kit": "materials/biome_alpine/",
			"surface_slots": [
				{"name": "ground", "weight": 1.0, "selector": {
					"elevation_m": [-50.0, 5.0],
					"slope_deg": [0.0, 20.0],
				}},
			],
			"auto_biome_rules": {"elevation_m": [-50.0, 50.0], "slope_deg": [0.0, 90.0]},
			"nav_default": "walkable",
		}],
	})
	var bc: BiomeCatalog = BiomeCatalog.from_file(path)
	assert_not_null(bc)
	assert_eq(bc.world_name, "test")
	assert_eq(bc.biomes.size(), 1)
	var b: Dictionary = bc.biomes[0]
	assert_eq(b["name"], "alpine")
	assert_eq((b["surface_slots"] as Array).size(), 1)


func test_load_missing_file_returns_null() -> void:
	var bc: BiomeCatalog = BiomeCatalog.from_file("user://does_not_exist.json")
	assert_null(bc)


func test_load_real_walking_demo_catalog() -> void:
	var bc: BiomeCatalog = BiomeCatalog.from_file(
		"res://addons/world5/worlds/walking_demo/biome_catalog.json")
	assert_not_null(bc, "walking_demo biome_catalog loads")
	var errors: Array = bc.validate()
	assert_eq(errors.size(), 0,
		"walking_demo biome_catalog valid (errors: %s)" % str(errors))
	assert_eq(bc.biomes.size(), 1, "walking demo is single-biome (alpine)")
	var alpine: Dictionary = bc.biomes[0]
	assert_eq(alpine["name"], "alpine")
	assert_eq((alpine["surface_slots"] as Array).size(), 3,
		"alpine declares 3 slots: ground/mid/rock")


# --- validation rules ---

func test_no_biomes_rejected() -> void:
	var path: String = _write("no_biomes", {
		"world_name": "empty",
		"biomes": [],
	})
	var bc: BiomeCatalog = BiomeCatalog.from_file(path)
	var errors: Array = bc.validate()
	assert_gt(errors.size(), 0, "catalog with 0 biomes must error")


func test_biome_missing_name_rejected() -> void:
	var path: String = _write("no_name", {
		"world_name": "x",
		"biomes": [{"kernel": {}, "surface_slots": []}],
	})
	var bc: BiomeCatalog = BiomeCatalog.from_file(path)
	var errors: Array = bc.validate()
	assert_gt(errors.size(), 0)


func test_slot_count_over_cap_rejected() -> void:
	# Spec 23 hard cap is 8 slots per biome
	var slots: Array = []
	for i in range(10):
		slots.append({"name": "s%d" % i, "weight": 1.0, "selector": {}})
	var path: String = _write("too_many_slots", {
		"world_name": "x",
		"biomes": [{
			"name": "b",
			"kernel": {"type": "noise_stack"},
			"surface_slots": slots,
		}],
	})
	var bc: BiomeCatalog = BiomeCatalog.from_file(path)
	var errors: Array = bc.validate()
	assert_gt(errors.size(), 0,
		"slot count > 8 must error (shader hard cap; spec 23)")


# --- queries ---

func test_biome_by_name() -> void:
	var path: String = _write("named_biome", {
		"world_name": "x",
		"biomes": [
			{"name": "alpine", "kernel": {"type": "noise_stack"}, "surface_slots": []},
			{"name": "forest", "kernel": {"type": "noise_stack"}, "surface_slots": []},
		],
	})
	var bc: BiomeCatalog = BiomeCatalog.from_file(path)
	var alpine: Dictionary = bc.biome_by_name("alpine")
	assert_eq(alpine.get("name", ""), "alpine")
	var missing: Dictionary = bc.biome_by_name("missing")
	assert_eq(missing.size(), 0, "unknown biome returns empty dict")


func test_slot_selector_fields_preserved() -> void:
	# The selector dict must round-trip intact — the shader-side slot
	# weight computation reads elevation_m + slope_deg + band_width
	# fields from here.
	var path: String = _write("selector_fields", {
		"world_name": "x",
		"biomes": [{
			"name": "alpine",
			"kernel": {"type": "noise_stack"},
			"surface_slots": [{
				"name": "ground",
				"weight": 1.0,
				"selector": {
					"elevation_m": [-10.0, 5.0],
					"slope_deg": [0.0, 20.0],
					"band_width_elevation_m": 8.0,
					"band_width_slope_deg": 5.0,
				},
			}],
		}],
	})
	var bc: BiomeCatalog = BiomeCatalog.from_file(path)
	var biome: Dictionary = bc.biome_by_name("alpine")
	var slot: Dictionary = (biome["surface_slots"] as Array)[0]
	var sel: Dictionary = slot["selector"]
	var elev: Array = sel["elevation_m"]
	assert_almost_eq(float(elev[0]), -10.0, 1e-5)
	assert_almost_eq(float(elev[1]),   5.0, 1e-5)
	assert_almost_eq(float(sel["band_width_elevation_m"]), 8.0, 1e-5)
