## Tests for NoiseStackKernel.gd — GD wrapper for fBm kernel config.
##
## Per spec 19. This wraps the config + emits dispatch params for the
## GPU compute backend. Cross-impl parity vs Python is in
## tests/integration/test_terrain_backend_parity.py.

extends GutTest


func test_constructible_with_defaults() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.new()
	assert_eq(k.octaves, 6)
	assert_almost_eq(k.frequency, 1.0 / 512.0, 1e-9)
	assert_eq(k.lacunarity, 2.0)
	assert_eq(k.gain, 0.5)
	assert_eq(k.amplitude, 50.0)


func test_from_dict_overrides() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.from_dict({
		"octaves": 4,
		"frequency": 0.01,
		"lacunarity": 2.5,
		"gain": 0.4,
		"amplitude": 100.0,
	})
	assert_eq(k.octaves, 4)
	assert_eq(k.frequency, 0.01)
	assert_eq(k.lacunarity, 2.5)
	assert_eq(k.gain, 0.4)
	assert_eq(k.amplitude, 100.0)


func test_from_dict_partial_keeps_defaults() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.from_dict({"amplitude": 25.0})
	assert_eq(k.amplitude, 25.0)
	assert_eq(k.octaves, 6, "other fields keep defaults")


# --- validate() ---

func test_validate_defaults_pass() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.new()
	assert_eq(k.validate().size(), 0)


func test_validate_zero_octaves_rejected() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.new()
	k.octaves = 0
	assert_gt(k.validate().size(), 0)


func test_validate_negative_amplitude_rejected() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.new()
	k.amplitude = -1.0
	assert_gt(k.validate().size(), 0)


func test_validate_zero_frequency_rejected() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.new()
	k.frequency = 0.0
	assert_gt(k.validate().size(), 0)


# --- config_hash (content-addressed, deterministic) ---

func test_config_hash_deterministic() -> void:
	var a: NoiseStackKernel = NoiseStackKernel.new()
	var b: NoiseStackKernel = NoiseStackKernel.new()
	assert_eq(a.config_hash(), b.config_hash())


func test_config_hash_differs_on_octaves() -> void:
	var a: NoiseStackKernel = NoiseStackKernel.new()
	var b: NoiseStackKernel = NoiseStackKernel.new()
	b.octaves = 8
	assert_ne(a.config_hash(), b.config_hash())


func test_config_hash_differs_on_amplitude() -> void:
	var a: NoiseStackKernel = NoiseStackKernel.new()
	var b: NoiseStackKernel = NoiseStackKernel.new()
	b.amplitude = 100.0
	assert_ne(a.config_hash(), b.config_hash())


func test_config_hash_is_sha256_hex() -> void:
	var k: NoiseStackKernel = NoiseStackKernel.new()
	assert_eq(k.config_hash().length(), 64)


# --- to_dict round-trip ---

func test_to_dict_round_trips() -> void:
	var a: NoiseStackKernel = NoiseStackKernel.from_dict({
		"octaves": 7, "frequency": 0.005, "lacunarity": 2.1,
		"gain": 0.45, "amplitude": 75.0,
	})
	var b: NoiseStackKernel = NoiseStackKernel.from_dict(a.to_dict())
	assert_eq(a.config_hash(), b.config_hash())
