## Tests TerrainWorld's quality-tier runtime defaults.

extends GutTest


func before_each() -> void:
	QualityTiers._reset_cache()


func test_quality_tier_defaults_apply_when_exports_are_default() -> void:
	var tw: TerrainWorld = TerrainWorld.new()
	tw.quality_tier_override = "low"
	add_child_autofree(tw)
	await get_tree().process_frame

	assert_eq(tw.ring_count, 3)
	assert_eq(tw.ring_vertex_grid, 128)
	assert_almost_eq(tw.inner_cell_size_m, 0.5, 0.001)
	assert_eq(tw.terrain_pages_max, 32)
	assert_eq((tw.get_debug_state()["rings"] as Array).size(), 3)


func test_quality_tier_defaults_preserve_explicit_scene_overrides() -> void:
	var tw: TerrainWorld = TerrainWorld.new()
	tw.quality_tier_override = "low"
	tw.ring_count = 2
	tw.ring_vertex_grid = 16
	tw.inner_cell_size_m = 1.0
	tw.terrain_pages_max = 8
	add_child_autofree(tw)
	await get_tree().process_frame

	assert_eq(tw.ring_count, 2)
	assert_eq(tw.ring_vertex_grid, 16)
	assert_almost_eq(tw.inner_cell_size_m, 1.0, 0.001)
	assert_eq(tw.terrain_pages_max, 8)
	assert_eq((tw.get_debug_state()["rings"] as Array).size(), 2)


func test_high_tier_budget_covers_default_visible_working_set() -> void:
	var tw: TerrainWorld = TerrainWorld.new()
	tw.quality_tier_override = "high"
	add_child_autofree(tw)
	await get_tree().process_frame

	var cache: TerrainPageCache = tw.get("_cache") as TerrainPageCache
	assert_not_null(cache)
	assert_eq(tw.ring_count, 5)
	assert_eq(tw.terrain_pages_max, 128)
	assert_gte(cache.budget, tw._minimum_visible_height_pages())
