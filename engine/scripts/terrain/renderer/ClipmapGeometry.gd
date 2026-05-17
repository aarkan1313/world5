## ClipmapGeometry — cold-builds the N concentric ring meshes once at
## startup.
##
## Per spec 21 module decomposition. Each ring is a grid_n × grid_n
## vertex grid centered on the world origin. Ring r has cell size
## inner_cell * 2^r so its extent doubles per ring.
##
## At runtime, ClipmapDispatch translates each ring (via
## ClipmapRing.set_center) to follow the camera; this class never
## modifies geometry after build.
##
## Phase 4.4.a deliberately ships the FULL square grid per ring (not
## the L-shaped donut clipmap variant). Future optimization (Phase 4.5
## calibration sprint) may swap to L-shape if profiling shows the
## inner-ring overdraw is significant. For Phase 4 MVP, square +
## per-ring height texture is simpler and correctness-first.

class_name ClipmapGeometry extends RefCounted


## Build N ring meshes. Returns an Array[ArrayMesh] (one per ring).
## Returns empty Array on invalid inputs.
##
## - ring_count: number of concentric rings (>= 1)
## - grid_n: vertices per side (>= 2)
## - inner_cell_m: cell size of ring 0 in meters (> 0)
func build(ring_count: int, grid_n: int, inner_cell_m: float) -> Array:
	if ring_count <= 0 or grid_n < 2 or inner_cell_m <= 0.0:
		return []
	var meshes: Array = []
	for r in range(ring_count):
		var cell_m: float = inner_cell_m * pow(2.0, r)
		meshes.append(_build_ring_mesh(grid_n, cell_m))
	return meshes


# --- internal ---

func _build_ring_mesh(grid_n: int, cell_m: float) -> ArrayMesh:
	# Vertex grid: (grid_n × grid_n) verts, centered on origin
	# Extent = (grid_n - 1) * cell_m
	# Vertex at (col, row) has world XZ = (col - (n-1)/2) * cell_m
	var half_extent: float = float(grid_n - 1) * cell_m * 0.5
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	verts.resize(grid_n * grid_n)
	normals.resize(grid_n * grid_n)
	uvs.resize(grid_n * grid_n)
	for row in range(grid_n):
		for col in range(grid_n):
			var x: float = float(col) * cell_m - half_extent
			var z: float = float(row) * cell_m - half_extent
			var idx: int = row * grid_n + col
			# Y=0; vertex shader displaces from heightmap sample
			verts[idx] = Vector3(x, 0.0, z)
			normals[idx] = Vector3.UP
			# UV in [0,1] for heightmap sampling
			uvs[idx] = Vector2(float(col) / float(grid_n - 1),
				float(row) / float(grid_n - 1))

	# Index buffer: two triangles per quad, (n-1)*(n-1) quads
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((grid_n - 1) * (grid_n - 1) * 6)
	var ii: int = 0
	for row in range(grid_n - 1):
		for col in range(grid_n - 1):
			var tl: int = row * grid_n + col
			var tr: int = tl + 1
			var bl: int = tl + grid_n
			var br: int = bl + 1
			# Two triangles, front-facing from above in Godot's renderer.
			indices[ii] = tl;     ii += 1
			indices[ii] = tr;     ii += 1
			indices[ii] = bl;     ii += 1
			indices[ii] = tr;     ii += 1
			indices[ii] = br;     ii += 1
			indices[ii] = bl;     ii += 1

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Note: mesh.custom_aabb here does NOT affect frustum culling in
	# Godot 4.6 — MeshInstance3D computes culling from CPU vertex data
	# and ignores the ArrayMesh override. The live AABB override is on
	# MeshInstance3D in ClipmapRing.configure (same ±500m Y intent).
	# We keep this so the mesh resource carries the right metadata for
	# any non-renderer consumer (raycast/physics setup, debug overlays).
	var aabb: AABB = AABB(
		Vector3(-half_extent, -500.0, -half_extent),
		Vector3(float(grid_n - 1) * cell_m, 1000.0, float(grid_n - 1) * cell_m)
	)
	mesh.surface_set_material(0, null)
	mesh.custom_aabb = aabb
	return mesh
