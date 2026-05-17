## Cross-impl parity emitter — runs as a gut test but its job is to
## emit canonical JSON values that the Python driver
## (tests/integration/test_cross_impl_diff.py) compares against the
## Python equivalents.
##
## Per SA2-C2.1: spec 13's "0 differences between Python and GDScript
## resolvers" claim was previously asserted independently per side
## without a real diff. This emitter + the Python driver close the gap.
##
## Output: writes JSON snapshots to user://_cross_impl_emit/ which the
## Python side reads + diffs.

extends GutTest


const _OUT_DIR := "user://_cross_impl_emit/"


func before_all() -> void:
	# Ensure output dir exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_OUT_DIR))


func _write(filename: String, content: String) -> void:
	var path := _OUT_DIR + filename
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "could open %s for write" % path)
	file.store_string(content)
	file.close()


# --- QualityTiers ---

func test_emit_quality_tiers_high() -> void:
	var tier := QualityTiers.get_tier("high")
	# Canonical sort: same keys order as Python
	var sorted_keys := tier.keys()
	sorted_keys.sort()
	var ordered := {}
	for k in sorted_keys:
		ordered[k] = tier[k]
	_write("quality_tiers_high.json", JSON.stringify(ordered))


func test_emit_quality_tiers_all() -> void:
	for name in QualityTiers.TIER_NAMES:
		var tier := QualityTiers.get_tier(name)
		var sorted_keys := tier.keys()
		sorted_keys.sort()
		var ordered := {}
		for k in sorted_keys:
			ordered[k] = tier[k]
		_write("quality_tiers_%s.json" % name, JSON.stringify(ordered))


# --- ContentAddress (canonical-JSON hash) ---

func test_emit_content_address_hashes() -> void:
	# Same inputs as Python's parity test
	var test_cases := [
		{"name": "empty", "input": {}},
		{"name": "simple", "input": {"a": 1, "b": "two", "c": true}},
		{"name": "nested",
		 "input": {"outer": "v", "inner": {"a": 1, "b": [1, 2, 3]}}},
		{"name": "list_of_ints", "input": {"arr": [1, 2, 3, 4, 5]}},
		{"name": "mixed_types",
		 "input": {"int": 42, "float": 3.14, "str": "hi", "bool": false}},
	]
	var results := {}
	for case in test_cases:
		results[case["name"]] = ContentAddress.compute_stamp(case["input"])
	_write("content_address_hashes.json", JSON.stringify(results))


# --- SpatialIndex (query results from fixed insert sequence) ---

func test_emit_spatial_index_queries() -> void:
	var idx := SpatialIndex.new(Rect2(-100, -100, 200, 200), 10.0)
	# Same insert sequence as Python parity test
	var inserts := [
		[1, Vector2(0.0, 0.0)],
		[2, Vector2(5.0, 5.0)],
		[3, Vector2(50.0, 50.0)],
		[4, Vector2(-30.0, 20.0)],
		[5, Vector2(0.1, 0.1)],
	]
	for ins in inserts:
		idx.insert(ins[0], ins[1])

	var results := {
		"query_radius_origin_1m": Array(idx.query_radius(Vector2(0, 0), 1.0)),
		"query_radius_origin_50m": Array(idx.query_radius(Vector2(0, 0), 50.0)),
		"query_rect_neg1_to_10": Array(idx.query_rect(Rect2(-1, -1, 11, 11))),
		"query_nearest_origin_3": Array(idx.query_nearest(Vector2(0, 0), 3)),
		"query_nearest_corner_2": Array(idx.query_nearest(Vector2(50, 50), 2)),
		"size": idx.size(),
		"bucket_count": idx.bucket_count(),
	}
	_write("spatial_index_queries.json", JSON.stringify(results))
