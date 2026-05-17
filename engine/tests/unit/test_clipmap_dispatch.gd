## Tests for ClipmapDispatch — per-frame ring update.

extends GutTest


var _geom: ClipmapGeometry
var _rings_to_free: Array = []


func before_each() -> void:
	_geom = ClipmapGeometry.new()
	_rings_to_free = []


func after_each() -> void:
	for r in _rings_to_free:
		if is_instance_valid(r.mesh_instance):
			r.mesh_instance.free()
	_rings_to_free.clear()


func _make_rings(ring_count: int = 4, grid_n: int = 16,
		inner_cell: float = 1.0) -> Array:
	var meshes: Array = _geom.build(ring_count, grid_n, inner_cell)
	var rings: Array = []
	for r in range(ring_count):
		var ring: ClipmapRing = ClipmapRing.new()
		ring.configure(meshes[r], r, inner_cell * pow(2.0, r))
		add_child(ring.mesh_instance)
		rings.append(ring)
		_rings_to_free.append(ring)
	return rings


func test_constructible() -> void:
	var dispatch: ClipmapDispatch = ClipmapDispatch.new()
	assert_not_null(dispatch)


func test_update_snaps_all_rings_to_camera() -> void:
	var rings: Array = _make_rings(3, 16, 1.0)
	var dispatch: ClipmapDispatch = ClipmapDispatch.new()
	dispatch.update(rings, Vector3(100.0, 50.0, 200.0))
	# Each ring snaps to its own cell grid
	assert_almost_eq(rings[0].snapped_center.x, 100.0, 1e-5,
		"ring 0 (cell 1m) snaps exactly")
	# Ring 1 cell = 2m, 100/2 = 50 -> snapped 100
	assert_almost_eq(rings[1].snapped_center.x, 100.0, 1e-5)
	# Ring 2 cell = 4m, 100/4 = 25 -> snapped 100
	assert_almost_eq(rings[2].snapped_center.x, 100.0, 1e-5)


func test_update_only_uses_camera_xz() -> void:
	var rings: Array = _make_rings(2, 16, 1.0)
	var dispatch: ClipmapDispatch = ClipmapDispatch.new()
	dispatch.update(rings, Vector3(10.0, 999.0, 20.0))
	assert_almost_eq(rings[0].mesh_instance.position.y, 0.0, 1e-5,
		"rings stay at Y=0 regardless of camera height")
	assert_almost_eq(rings[0].snapped_center.x, 10.0, 1e-5)


# --- morph factor compute ---

func test_morph_factor_inside_band_is_zero() -> void:
	# Camera near the ring center (well inside the morph-stable region)
	var dispatch: ClipmapDispatch = ClipmapDispatch.new()
	var morph: float = dispatch.compute_morph_factor(
		Vector2(0.0, 0.0),      # camera xz
		Vector2(0.0, 0.0),      # ring center
		100.0,                  # ring half-extent
		0.16,                   # band fraction
	)
	assert_eq(morph, 0.0, "center → no morph")


func test_morph_factor_outside_band_is_one() -> void:
	var dispatch: ClipmapDispatch = ClipmapDispatch.new()
	# Camera at 95m from center; ring half = 100, morph band = 0.16
	# Band starts at half * (1 - band_frac) = 100 * 0.84 = 84
	# Band ends at half = 100. Camera at 95 = (95-84)/(100-84) = 0.6875
	# Actually morph is computed from inner-edge distance — 95 inside
	# the band but most of the way through.
	var morph: float = dispatch.compute_morph_factor(
		Vector2(105.0, 0.0),    # camera xz beyond ring extent
		Vector2(0.0, 0.0),
		100.0,
		0.16,
	)
	assert_eq(morph, 1.0, "beyond extent → fully morphed")


func test_morph_factor_in_band_is_partial() -> void:
	var dispatch: ClipmapDispatch = ClipmapDispatch.new()
	# Camera at 92m from center; ring half=100, band=0.16 → starts 84
	# Fraction = (92 - 84) / (100 - 84) = 8/16 = 0.5
	var morph: float = dispatch.compute_morph_factor(
		Vector2(92.0, 0.0),
		Vector2(0.0, 0.0),
		100.0,
		0.16,
	)
	assert_almost_eq(morph, 0.5, 0.01)


func test_morph_factor_uses_chebyshev_distance() -> void:
	# Clipmap rings are squares; morph should use max(|dx|,|dz|) not Euclidean
	var dispatch: ClipmapDispatch = ClipmapDispatch.new()
	# Camera at (90, 0) vs (90, 90): same chebyshev = 90
	var m1: float = dispatch.compute_morph_factor(
		Vector2(90.0, 0.0), Vector2.ZERO, 100.0, 0.16)
	var m2: float = dispatch.compute_morph_factor(
		Vector2(90.0, 90.0), Vector2.ZERO, 100.0, 0.16)
	assert_almost_eq(m1, m2, 0.001, "chebyshev distance, not euclidean")
