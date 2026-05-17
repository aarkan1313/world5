## Tests for TerrainPageRequest — request shape for terrain backend.
##
## Per spec 20 page contract. Validates field defaults, capability
## vocabulary enforcement, cache-key composition.

extends GutTest


const VALID_CAPS := [
	"height_gpu", "height_cpu", "collision_height", "slope",
	"nav_traversability", "biome_mask_gpu", "biome_mask_cpu",
	"drainage_map", "flow_direction",
]


# --- field shape + defaults ---

func test_default_fields_present() -> void:
	var req: TerrainPageRequest = TerrainPageRequest.new()
	assert_true(req.world_xz is Vector2)
	assert_true(req.extent_m is float)
	assert_true(req.grid_n is int)
	assert_true(req.seed is int)
	assert_true(req.tier is String)
	assert_true(req.capabilities is PackedStringArray)


func test_construct_from_dict() -> void:
	var req: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2(100.0, 200.0),
		"extent_m": 256.0,
		"grid_n": 256,
		"seed": 42,
		"tier": "high",
		"capabilities": ["height_gpu", "slope"],
	})
	assert_eq(req.world_xz, Vector2(100.0, 200.0))
	assert_eq(req.extent_m, 256.0)
	assert_eq(req.grid_n, 256)
	assert_eq(req.seed, 42)
	assert_eq(req.tier, "high")
	assert_eq(Array(req.capabilities), ["height_gpu", "slope"])


# --- capability validation per spec 20 vocabulary ---

func test_valid_capabilities_accepted() -> void:
	for cap in VALID_CAPS:
		var req: TerrainPageRequest = TerrainPageRequest.new()
		req.capabilities = PackedStringArray([cap])
		var errors := req.validate()
		assert_eq(errors.size(), 0, "%s should be valid: %s" % [cap, errors])


func test_invalid_capability_rejected() -> void:
	var req: TerrainPageRequest = TerrainPageRequest.new()
	req.capabilities = PackedStringArray(["height_gpu", "bogus_cap"])
	var errors := req.validate()
	assert_gt(errors.size(), 0, "bogus_cap should be flagged")
	var msg := str(errors)
	assert_true("bogus_cap" in msg, "error should name the bad cap: %s" % msg)


func test_empty_capabilities_rejected() -> void:
	var req: TerrainPageRequest = TerrainPageRequest.new()
	req.world_xz = Vector2.ZERO
	req.extent_m = 256.0
	req.grid_n = 256
	req.capabilities = PackedStringArray()
	var errors := req.validate()
	assert_gt(errors.size(), 0, "empty capabilities is a no-op request")


# --- grid_n + extent sanity ---

func test_zero_grid_n_rejected() -> void:
	var req: TerrainPageRequest = TerrainPageRequest.new()
	req.grid_n = 0
	req.extent_m = 256.0
	req.capabilities = PackedStringArray(["height_gpu"])
	var errors := req.validate()
	assert_gt(errors.size(), 0)


func test_zero_extent_rejected() -> void:
	var req: TerrainPageRequest = TerrainPageRequest.new()
	req.grid_n = 256
	req.extent_m = 0.0
	req.capabilities = PackedStringArray(["height_gpu"])
	var errors := req.validate()
	assert_gt(errors.size(), 0)


# --- cache key composition (per spec 12 content addressing) ---

func test_cache_key_deterministic() -> void:
	var a: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2(100.0, 200.0),
		"extent_m": 256.0,
		"grid_n": 256,
		"seed": 42,
		"tier": "high",
		"capabilities": ["height_gpu"],
	})
	var b: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2(100.0, 200.0),
		"extent_m": 256.0,
		"grid_n": 256,
		"seed": 42,
		"tier": "high",
		"capabilities": ["height_gpu"],
	})
	assert_eq(a.cache_key(), b.cache_key())


func test_cache_key_differs_on_position() -> void:
	var a: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2(100.0, 200.0),
		"extent_m": 256.0, "grid_n": 256, "seed": 42, "tier": "high",
		"capabilities": ["height_gpu"],
	})
	var b: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2(300.0, 200.0),
		"extent_m": 256.0, "grid_n": 256, "seed": 42, "tier": "high",
		"capabilities": ["height_gpu"],
	})
	assert_ne(a.cache_key(), b.cache_key())


func test_cache_key_order_independent_for_capabilities() -> void:
	# Two requests differing only in capability order should hit same cache
	var a: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2.ZERO, "extent_m": 256.0, "grid_n": 256,
		"seed": 0, "tier": "high",
		"capabilities": ["height_gpu", "slope"],
	})
	var b: TerrainPageRequest = TerrainPageRequest.from_dict({
		"world_xz": Vector2.ZERO, "extent_m": 256.0, "grid_n": 256,
		"seed": 0, "tier": "high",
		"capabilities": ["slope", "height_gpu"],
	})
	assert_eq(a.cache_key(), b.cache_key())
