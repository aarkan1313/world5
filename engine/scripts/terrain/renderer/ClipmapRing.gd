## ClipmapRing — one ring in the clipmap.
##
## Per spec 21 module decomposition. Owns:
##   - one MeshInstance3D (the ring's cold-built geometry)
##   - its LOD level + cell size
##   - the camera-snapped center
##
## set_center(world_xz) snaps to the ring's cell grid (so the ring
## moves in cell-sized steps to keep the mesh stationary in pixel
## space). ClipmapDispatch calls this each frame as the camera moves.

class_name ClipmapRing extends RefCounted


## LOD level (0 = innermost). Ring N+1 covers 2× the area at ½ density.
var level: int = 0
## Cell size in world meters for this ring's grid.
var cell_size_m: float = 1.0
## Cell-aligned snap of the requested center. Read after set_center.
var snapped_center: Vector2 = Vector2.ZERO
## The Node3D that renders this ring. Configured in configure().
var mesh_instance: MeshInstance3D = null


func _init() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ClipmapRing"
	# Phase 4 renders full square rings that overlap. Letting every
	# overlapping LOD cast shadows produces view-dependent self-shadow
	# wedges; terrain can still receive shadows from other scene objects.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Bind to a built mesh. cell_size_m matches ClipmapGeometry's
## inner_cell_m * 2^level.
func configure(mesh: Mesh, ring_level: int, cell_m: float) -> void:
	level = ring_level
	cell_size_m = cell_m
	mesh_instance.mesh = mesh
	mesh_instance.name = "ClipmapRing_L%d" % level
	# Vertex shader displaces verts on Y per the heightmap — but CPU
	# verts are flat at y=0, so the mesh's auto-AABB has zero Y extent
	# and the whole ring frustum-culls the moment displacement pushes
	# any visible vertex off the y=0 plane (e.g. unbound height_map
	# samples to 0, then shader maps that to y = -height_scale).
	# ArrayMesh.custom_aabb is not picked up by MeshInstance3D culling
	# in Godot 4.6 — the override has to live on the MeshInstance3D.
	# Match ClipmapGeometry's intended ±500 m Y bound.
	var local_aabb: AABB = mesh.get_aabb() if mesh != null else AABB()
	mesh_instance.custom_aabb = AABB(
		Vector3(local_aabb.position.x, -500.0, local_aabb.position.z),
		Vector3(local_aabb.size.x, 1000.0, local_aabb.size.z))


## Snap to the ring's cell grid + translate the mesh to that position.
## Returns the snapped center as a convenience.
func set_center(world_xz: Vector2) -> Vector2:
	# Snap to nearest cell-grid point
	snapped_center = Vector2(
		round(world_xz.x / cell_size_m) * cell_size_m,
		round(world_xz.y / cell_size_m) * cell_size_m,
	)
	mesh_instance.position = Vector3(snapped_center.x, 0.0, snapped_center.y)
	return snapped_center


## World-space AABB of the ring at its current position.
func world_aabb() -> AABB:
	if mesh_instance.mesh == null:
		return AABB()
	var local_aabb: AABB = mesh_instance.mesh.get_aabb()
	# Translate by mesh position
	return AABB(
		local_aabb.position + mesh_instance.position,
		local_aabb.size,
	)
