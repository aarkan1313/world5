## Tests for ClipmapRing — one ring's MeshInstance3D + snap.

extends GutTest


var _geom: ClipmapGeometry
var _rings_to_free: Array = []


func before_each() -> void:
	_geom = ClipmapGeometry.new()
	_rings_to_free = []


func after_each() -> void:
	# Free MeshInstance3D's immediately (not queue_free) so their
	# rendering-server Instance RIDs drop before the next test
	# file's autoload teardown checks for leaks.
	for r in _rings_to_free:
		if is_instance_valid(r.mesh_instance):
			r.mesh_instance.free()
	_rings_to_free.clear()


func _make_ring(level: int = 0, grid_n: int = 16,
		inner_cell_m: float = 1.0) -> ClipmapRing:
	var meshes: Array = _geom.build(level + 1, grid_n, inner_cell_m)
	var ring: ClipmapRing = ClipmapRing.new()
	ring.configure(meshes[level], level, inner_cell_m * pow(2.0, level))
	# Add to scene tree so Godot manages the rendering-server Instance
	# RID; after_each free()'s immediately to drop it before next test.
	add_child(ring.mesh_instance)
	_rings_to_free.append(ring)
	return ring


func test_constructible() -> void:
	var ring: ClipmapRing = ClipmapRing.new()
	_rings_to_free.append(ring)
	assert_not_null(ring)


func test_ring_mesh_does_not_cast_self_shadows() -> void:
	var ring: ClipmapRing = ClipmapRing.new()
	_rings_to_free.append(ring)
	assert_eq(ring.mesh_instance.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_configure_sets_level_and_cell_size() -> void:
	var ring: ClipmapRing = _make_ring(2, 16, 1.0)
	assert_eq(ring.level, 2)
	assert_eq(ring.cell_size_m, 4.0, "level 2 cell = inner * 2^2")


func test_set_center_snaps_to_cell_grid() -> void:
	var ring: ClipmapRing = _make_ring(0, 16, 4.0)
	# Camera at 5.0, snap to nearest 4m cell -> 4.0
	ring.set_center(Vector2(5.0, 5.0))
	assert_almost_eq(ring.snapped_center.x, 4.0, 1e-5)
	assert_almost_eq(ring.snapped_center.y, 4.0, 1e-5)


func test_set_center_snap_negative() -> void:
	var ring: ClipmapRing = _make_ring(1, 16, 1.0)  # cell 2m
	ring.set_center(Vector2(-3.5, -3.5))
	# Snap to nearest 2m -> -4.0
	assert_almost_eq(ring.snapped_center.x, -4.0, 1e-5)
	assert_almost_eq(ring.snapped_center.y, -4.0, 1e-5)


func test_set_center_updates_mesh_position() -> void:
	var ring: ClipmapRing = _make_ring(0, 16, 1.0)
	ring.set_center(Vector2(100.0, 200.0))
	var mi: MeshInstance3D = ring.mesh_instance
	assert_almost_eq(mi.position.x, 100.0, 1e-5)
	assert_almost_eq(mi.position.z, 200.0, 1e-5)


func test_world_aabb_reflects_position() -> void:
	var ring: ClipmapRing = _make_ring(0, 16, 1.0)
	ring.set_center(Vector2(100.0, 0.0))
	var aabb: AABB = ring.world_aabb()
	# Ring 0 extent = 15m; centered at (100, 0)
	assert_almost_eq(aabb.position.x, 100.0 - 7.5, 0.1)
	assert_almost_eq(aabb.position.z, -7.5, 0.1)


func test_configure_with_null_mesh_fails_gracefully() -> void:
	var ring: ClipmapRing = ClipmapRing.new()
	_rings_to_free.append(ring)
	ring.configure(null, 0, 1.0)
	# Should not crash; mesh_instance.mesh remains null
	assert_null(ring.mesh_instance.mesh)
