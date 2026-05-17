## Tests for TerrainPageResult — result shape from terrain backend.
##
## Per spec 20 page contract. Validates field shape, capability →
## populated-field mapping, ready-state checks.

extends GutTest


func _make_req(caps: Array) -> TerrainPageRequest:
	return TerrainPageRequest.from_dict({
		"world_xz": Vector2(0.0, 0.0),
		"extent_m": 256.0, "grid_n": 256, "seed": 0, "tier": "high",
		"capabilities": caps,
	})


# --- field shape + defaults ---

func test_default_fields_present() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	assert_null(res.request)
	assert_eq(res.cache_key, "")
	assert_true(res.version_stamp is Dictionary)


func test_request_round_trips() -> void:
	var req: TerrainPageRequest = _make_req(["height_gpu"])
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = req
	res.cache_key = req.cache_key()
	assert_eq(res.request, req)
	assert_eq(res.cache_key, req.cache_key())


# --- capability → populated-field mapping ---

func test_has_capability_height_cpu() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = _make_req(["height_cpu"])
	# Initially no data: has_capability returns false
	assert_false(res.has_capability("height_cpu"))
	# After populating: returns true
	res.height_cpu = PackedFloat32Array([0.0, 1.0, 2.0, 3.0])
	assert_true(res.has_capability("height_cpu"))


func test_has_capability_slope() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = _make_req(["slope"])
	assert_false(res.has_capability("slope"))
	res.slope = PackedFloat32Array([0.0, 0.1])
	assert_true(res.has_capability("slope"))


func test_has_capability_collision_height() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = _make_req(["collision_height"])
	assert_false(res.has_capability("collision_height"))
	res.collision_height = PackedFloat32Array([0.0])
	assert_true(res.has_capability("collision_height"))


func test_has_capability_unknown_returns_false() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = _make_req(["height_cpu"])
	assert_false(res.has_capability("bogus_cap"))


# --- ready check: are all requested capabilities populated? ---

func test_is_complete_when_all_capabilities_populated() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = _make_req(["height_cpu", "slope"])
	res.height_cpu = PackedFloat32Array([0.0])
	res.slope = PackedFloat32Array([0.0])
	assert_true(res.is_complete())


func test_is_not_complete_when_capability_missing() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.request = _make_req(["height_cpu", "slope"])
	res.height_cpu = PackedFloat32Array([0.0])
	# slope not set
	assert_false(res.is_complete())


# --- version stamp per spec 17 ---

func test_version_stamp_populated() -> void:
	var res: TerrainPageResult = TerrainPageResult.new()
	res.version_stamp = {
		"backend": "gpu",
		"backend_version": "0.0.1",
		"kernel_version": "0.0.1",
	}
	assert_eq(res.version_stamp["backend"], "gpu")
