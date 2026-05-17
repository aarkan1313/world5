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
