## QualityTiers GDScript-side parity test.
##
## Per spec 13 quality bar + spec 06 cross-impl pattern. The Python
## side (tests/integration/test_quality_tiers_cross_impl.py) validates
## the same canonical config. This gut test ensures the GDScript
## resolver loads the same file + returns the same shape.
##
## Run via verify --fast (this is a gut test under engine/tests/).

extends GutTest


func before_each() -> void:
	QualityTiers._reset_cache()


func test_canonical_config_loadable() -> void:
	var tiers := QualityTiers.load_config()
	assert_false(tiers.is_empty(), "quality_tiers.json loaded")


func test_all_tier_names_present() -> void:
	var tiers := QualityTiers.load_config()
	for name in QualityTiers.TIER_NAMES:
		assert_true(tiers.has(name), "tier '%s' present" % name)


func test_tier_dict_self_consistent() -> void:
	var tiers := QualityTiers.load_config()
	for name in tiers.keys():
		assert_eq(tiers[name]["tier_name"], name, "tier %s self-consistent" % name)


func test_frame_budget_engine_share_matches_x_frame_budget() -> void:
	var expected := {"low": 4.0, "medium": 6.0, "high": 8.0, "ultra": 10.0, "cinematic": 20.0}
	for name in expected.keys():
		var actual = QualityTiers.get_tier(name)["frame_budget_engine_share_ms"]
		assert_eq(actual, expected[name],
			"%s: engine_share_ms (X_FRAME_BUDGET parity)" % name)


func test_visibility_distance_monotone() -> void:
	var prev: int = 0
	for name in QualityTiers.TIER_NAMES:
		var d: int = QualityTiers.get_tier(name)["visibility_ship_distance_m"]
		if prev != 0:
			assert_gt(d, prev, "visibility distance grows %s > prev" % name)
		prev = d


func test_nav_grid_n_matches_spec_33() -> void:
	var expected := {"low": 32, "medium": 48, "high": 64, "ultra": 96, "cinematic": 128}
	for name in expected.keys():
		assert_eq(QualityTiers.get_tier(name)["nav_grid_n"], expected[name],
			"%s nav_grid_n" % name)


func test_terrain_step_n_matches_outer_ring_cell_size() -> void:
	for name in QualityTiers.TIER_NAMES:
		var tier: Dictionary = QualityTiers.get_tier(name)
		var rings: int = int(tier["terrain_rings"])
		var step0: float = float(tier["terrain_step0_m"])
		var expected_step_n: float = step0 * pow(2.0, rings - 1)
		assert_almost_eq(float(tier["terrain_stepN_m"]), expected_step_n, 0.001,
			"%s terrain_stepN_m matches step0 * 2^(rings - 1)" % name)


func test_terrain_cpu_page_budget_covers_visible_working_set() -> void:
	for name in QualityTiers.TIER_NAMES:
		var tier: Dictionary = QualityTiers.get_tier(name)
		var required: int = _visible_page_working_set(tier)
		assert_gte(int(tier["streaming_budget_cpu_pages"]), required,
			"%s cpu_pages budget covers current clipmap height arrays" % name)


func test_get_current_default_high() -> void:
	# No ProjectSettings override; default should be 'high'
	if ProjectSettings.has_setting("world5/quality_tier"):
		ProjectSettings.set_setting("world5/quality_tier", null)
	var current := QualityTiers.get_current()
	assert_eq(current["tier_name"], "high")


func test_names_returns_5_tiers() -> void:
	assert_eq(QualityTiers.names().size(), 5)


func test_load_idempotent() -> void:
	var first := QualityTiers.load_config()
	var second := QualityTiers.load_config()
	# Dictionary equality is structural in GDScript
	assert_eq(first, second, "load() is idempotent")


func _visible_page_working_set(tier: Dictionary) -> int:
	var total: int = 0
	var grid_n: int = int(tier["terrain_grid_n"])
	var step0: float = float(tier["terrain_step0_m"])
	var rings: int = int(tier["terrain_rings"])
	var page_extent_m: float = 256.0
	for ring in range(rings):
		var extent_m: float = float(grid_n - 1) * step0 * pow(2.0, ring)
		var raw: float = extent_m / page_extent_m
		var pages_per_side: int = 2 if raw <= 1.0 else int(ceil(raw)) + 1
		total += pages_per_side * pages_per_side
	return total
