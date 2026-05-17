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


## Bind to a built mesh. cell_size_m matches ClipmapGeometry's
## inner_cell_m * 2^level.
func configure(mesh: Mesh, ring_level: int, cell_m: float) -> void:
	level = ring_level
	cell_size_m = cell_m
	mesh_instance.mesh = mesh
	mesh_instance.name = "ClipmapRing_L%d" % level


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
