## Tests for ClipmapGeometry — cold-builds the N ring meshes.
##
## Per spec 21 + plan doc Phase 4.4.a. ClipmapGeometry is the
## one-shot mesh builder; verifies vertex counts, world-space bounds,
## inner-hole cap math. No GPU work here (pure geometry).

extends GutTest


# A typical ring config used across tests
const DEFAULT_RING_VERTS := 64   # smaller than spec default 256 for test speed
const DEFAULT_INNER_CELL := 1.0
const DEFAULT_RING_COUNT := 4


func test_constructible_with_defaults() -> void:
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	assert_not_null(geom)


func test_build_returns_one_mesh_per_ring() -> void:
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	var meshes: Array = geom.build(DEFAULT_RING_COUNT, DEFAULT_RING_VERTS,
		DEFAULT_INNER_CELL)
	assert_eq(meshes.size(), DEFAULT_RING_COUNT,
		"one mesh per ring")
	for m in meshes:
		assert_true(m is ArrayMesh, "each mesh is an ArrayMesh")


func test_ring_vertex_grid_size() -> void:
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	var meshes: Array = geom.build(1, DEFAULT_RING_VERTS, DEFAULT_INNER_CELL)
	var mesh: ArrayMesh = meshes[0]
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), DEFAULT_RING_VERTS * DEFAULT_RING_VERTS,
		"vertex count = grid_n * grid_n for a full square ring")


func test_ring_cell_size_doubles_per_ring() -> void:
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	var meshes: Array = geom.build(3, 16, 1.0)  # 3 rings, base cell 1m
	# Ring 0: 16x16 verts at 1m cell -> 15m extent
	# Ring 1: 16x16 verts at 2m cell -> 30m extent
	# Ring 2: 16x16 verts at 4m cell -> 60m extent
	var aabb_0: AABB = meshes[0].get_aabb()
	var aabb_1: AABB = meshes[1].get_aabb()
	var aabb_2: AABB = meshes[2].get_aabb()
	assert_almost_eq(aabb_0.size.x, 15.0, 0.01, "ring 0 extent = (n-1)*cell0")
	assert_almost_eq(aabb_1.size.x, 30.0, 0.01, "ring 1 extent = 2*ring0")
	assert_almost_eq(aabb_2.size.x, 60.0, 0.01, "ring 2 extent = 4*ring0")


func test_ring_meshes_share_pivot_at_origin() -> void:
	## The build produces ring meshes centered on (0,0,0). Camera-snap
	## later translates them via set_center. Geometry stage = local.
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	var meshes: Array = geom.build(1, 16, 1.0)
	var aabb: AABB = meshes[0].get_aabb()
	# AABB position is the min corner; for a 15m extent centered at 0,
	# min is (-7.5, ?, -7.5).
	assert_almost_eq(aabb.position.x, -7.5, 0.01)
	assert_almost_eq(aabb.position.z, -7.5, 0.01)


func test_invalid_ring_count_returns_empty() -> void:
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	assert_eq(geom.build(0, 16, 1.0).size(), 0, "ring_count=0 -> empty")
	assert_eq(geom.build(-1, 16, 1.0).size(), 0, "negative ring_count -> empty")


func test_invalid_grid_n_returns_empty() -> void:
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	assert_eq(geom.build(4, 1, 1.0).size(), 0, "grid_n=1 -> empty (no quads)")
	assert_eq(geom.build(4, 0, 1.0).size(), 0)


func test_mesh_has_uv_for_heightmap_sampling() -> void:
	var geom: ClipmapGeometry = ClipmapGeometry.new()
	var meshes: Array = geom.build(1, 16, 1.0)
	var arrays: Array = meshes[0].surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(uvs.size(), 16 * 16, "one UV per vertex")
