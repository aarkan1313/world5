## Tests for DemFeatureKernel.gd — GD wrapper for DEM feature extraction.
##
## Per spec 19 §"Kernel types shipped in v1" item 3. Cross-impl parity
## vs Python is in tests/integration/test_dem_feature_parity_real_device.gd
## (sprint 4; the bake-route v1 doesn't need parity since it CALLS the
## Python reference directly).

extends GutTest


func test_constructible_with_defaults() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.new()
	assert_eq(k.source, "")
	assert_eq(k.mode, DemFeatureKernel.MODE_RIDGE_EMPHASIS)
	assert_almost_eq(k.strength, 0.7, 1e-9)
	assert_almost_eq(k.ridge_smooth_sigma_cells, 2.0, 1e-9)
	assert_eq(k.seed, 42)


func test_from_dict_overrides() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.from_dict({
		"source": "cascades",
		"mode": "drainage_accumulation",
		"strength": 0.4,
		"ridge_smooth_sigma_cells": 3.0,
		"seed": 100,
	})
	assert_eq(k.source, "cascades")
	assert_eq(k.mode, "drainage_accumulation")
	assert_almost_eq(k.strength, 0.4, 1e-9)
	assert_almost_eq(k.ridge_smooth_sigma_cells, 3.0, 1e-9)
	assert_eq(k.seed, 100)


func test_from_dict_partial_keeps_defaults() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "mt_hood"})
	assert_eq(k.source, "mt_hood")
	assert_eq(k.mode, DemFeatureKernel.MODE_RIDGE_EMPHASIS, "default mode")


# --- validate ---

func test_validate_requires_source() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.new()
	assert_gt(k.validate().size(), 0)


func test_validate_passes_with_source() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.new()
	k.source = "cascades"
	assert_eq(k.validate().size(), 0)


func test_validate_rejects_unknown_mode() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.new()
	k.source = "cascades"
	k.mode = "made_up_mode"
	assert_gt(k.validate().size(), 0)


func test_validate_accepts_all_canonical_modes() -> void:
	for m in DemFeatureKernel.VALID_MODES:
		var k: DemFeatureKernel = DemFeatureKernel.new()
		k.source = "cascades"
		k.mode = m
		assert_eq(k.validate().size(), 0,
			"mode '%s' should validate" % m)


func test_validate_rejects_strength_above_one() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.new()
	k.source = "cascades"
	k.strength = 1.5
	assert_gt(k.validate().size(), 0)


func test_validate_rejects_negative_strength() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.new()
	k.source = "cascades"
	k.strength = -0.1
	assert_gt(k.validate().size(), 0)


func test_validate_rejects_zero_sigma() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.new()
	k.source = "cascades"
	k.ridge_smooth_sigma_cells = 0.0
	assert_gt(k.validate().size(), 0)


# --- config_hash ---

func test_config_hash_deterministic() -> void:
	var a: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "cascades"})
	var b: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "cascades"})
	assert_eq(a.config_hash(), b.config_hash())


func test_config_hash_differs_on_source() -> void:
	var a: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "cascades"})
	var b: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "yosemite"})
	assert_ne(a.config_hash(), b.config_hash())


func test_config_hash_differs_on_mode() -> void:
	var a: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "x", "mode": "ridge_emphasis"})
	var b: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "x", "mode": "drainage_accumulation"})
	assert_ne(a.config_hash(), b.config_hash())


func test_config_hash_differs_on_strength() -> void:
	var a: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "x", "strength": 0.3})
	var b: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "x", "strength": 0.6})
	assert_ne(a.config_hash(), b.config_hash())


func test_config_hash_is_sha256_hex() -> void:
	var k: DemFeatureKernel = DemFeatureKernel.from_dict({"source": "x"})
	assert_eq(k.config_hash().length(), 64)


# --- to_dict round-trip ---

func test_to_dict_round_trips() -> void:
	var a: DemFeatureKernel = DemFeatureKernel.from_dict({
		"source": "mt_hood", "mode": "slope_deg",
		"strength": 0.55, "ridge_smooth_sigma_cells": 2.5,
	})
	var b: DemFeatureKernel = DemFeatureKernel.from_dict(a.to_dict())
	assert_eq(a.config_hash(), b.config_hash())
