## Tests for ErosionKernel.gd — GD wrapper for hydraulic+thermal erosion config.
##
## Per spec 19. This wraps the config + emits dispatch params for the
## GPU compute backend. Cross-impl parity vs Python is in
## tests/integration/test_erosion_parity_real_device.gd.

extends GutTest


func test_constructible_with_defaults() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	assert_eq(k.iterations, 50)
	assert_almost_eq(k.rain_rate, 0.012, 1e-9)
	assert_almost_eq(k.evaporation, 0.015, 1e-9)
	assert_almost_eq(k.sediment_capacity, 0.10, 1e-9)
	assert_almost_eq(k.dissolve_rate, 0.30, 1e-9)
	assert_almost_eq(k.deposit_rate, 0.30, 1e-9)
	assert_almost_eq(k.min_slope, 0.005, 1e-9)
	assert_almost_eq(k.gravity, 9.81, 1e-9)
	assert_eq(k.thermal_iterations, 50)
	assert_almost_eq(k.talus_angle_deg, 30.0, 1e-9)
	assert_almost_eq(k.talus_rate, 0.25, 1e-9)
	assert_eq(k.seed, 42)


func test_from_dict_overrides() -> void:
	var k: ErosionKernel = ErosionKernel.from_dict({
		"iterations": 400,
		"rain_rate": 0.025,
		"evaporation": 0.02,
		"sediment_capacity": 0.15,
		"dissolve_rate": 0.40,
		"deposit_rate": 0.35,
		"thermal_iterations": 100,
		"talus_angle_deg": 35.0,
		"talus_rate": 0.30,
	})
	assert_eq(k.iterations, 400)
	assert_almost_eq(k.rain_rate, 0.025, 1e-9)
	assert_almost_eq(k.evaporation, 0.02, 1e-9)
	assert_eq(k.thermal_iterations, 100)
	assert_almost_eq(k.talus_angle_deg, 35.0, 1e-9)


func test_from_dict_partial_keeps_defaults() -> void:
	var k: ErosionKernel = ErosionKernel.from_dict({"iterations": 200})
	assert_eq(k.iterations, 200)
	assert_eq(k.thermal_iterations, 50, "other fields keep defaults")


# --- validate() ---

func test_validate_defaults_pass() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	assert_eq(k.validate().size(), 0)


func test_validate_zero_iterations_rejected() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	k.iterations = 0
	assert_gt(k.validate().size(), 0)


func test_validate_iterations_over_cap_rejected() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	k.iterations = 1001
	assert_gt(k.validate().size(), 0)


func test_validate_negative_rain_rejected() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	k.rain_rate = -0.01
	assert_gt(k.validate().size(), 0)


func test_validate_evaporation_above_one_rejected() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	k.evaporation = 1.5
	assert_gt(k.validate().size(), 0)


func test_validate_talus_angle_above_89_rejected() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	k.talus_angle_deg = 90.0
	assert_gt(k.validate().size(), 0)


func test_validate_talus_rate_above_one_rejected() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	k.talus_rate = 1.5
	assert_gt(k.validate().size(), 0)


func test_validate_zero_thermal_iterations_allowed() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	k.thermal_iterations = 0
	assert_eq(k.validate().size(), 0, "0 = thermal disabled, valid")


# --- config_hash (content-addressed, deterministic) ---

func test_config_hash_deterministic() -> void:
	var a: ErosionKernel = ErosionKernel.new()
	var b: ErosionKernel = ErosionKernel.new()
	assert_eq(a.config_hash(), b.config_hash())


func test_config_hash_differs_on_iterations() -> void:
	var a: ErosionKernel = ErosionKernel.new()
	var b: ErosionKernel = ErosionKernel.new()
	b.iterations = 100
	assert_ne(a.config_hash(), b.config_hash())


func test_config_hash_differs_on_talus_angle() -> void:
	var a: ErosionKernel = ErosionKernel.new()
	var b: ErosionKernel = ErosionKernel.new()
	b.talus_angle_deg = 45.0
	assert_ne(a.config_hash(), b.config_hash())


func test_config_hash_is_sha256_hex() -> void:
	var k: ErosionKernel = ErosionKernel.new()
	assert_eq(k.config_hash().length(), 64)


# --- to_dict round-trip ---

func test_to_dict_round_trips() -> void:
	var a: ErosionKernel = ErosionKernel.from_dict({
		"iterations": 200, "rain_rate": 0.02, "evaporation": 0.01,
		"sediment_capacity": 0.12, "thermal_iterations": 75,
		"talus_angle_deg": 32.0,
	})
	var b: ErosionKernel = ErosionKernel.from_dict(a.to_dict())
	assert_eq(a.config_hash(), b.config_hash())
