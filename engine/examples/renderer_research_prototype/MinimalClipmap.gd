## Minimal clipmap prototype (spec 15a section E validation).
##
## Builds a single 256x256 vertex grid mesh + displaces vertices via
## heightmap texture sampled in vertex shader. Validates the core
## clipmap primitive works in Godot 4.5 without engine extensions.
##
## NOT a production clipmap — no multi-ring, no streaming, no LOD
## morphing. Just proves the primitive renders + measures frame time.

class_name MinimalClipmap extends Node3D

@export var grid_n: int = 256  # vertices per side
@export var world_extent_m: float = 1000.0  # 1km × 1km
@export var height_scale_m: float = 100.0
@export var heightmap_texture: Texture2D
@export var frame_log_interval: int = 60  # log every N frames

var _mesh_instance: MeshInstance3D
var _frame_count: int = 0
var _frame_time_accum: float = 0.0
var _frame_time_min: float = 1e9
var _frame_time_max: float = 0.0
var _last_log_frame: int = 0


func _ready() -> void:
	_build_mesh()
	Log.info("clipmap_proto",
		"prototype ready",
		{"grid_n": grid_n, "extent_m": world_extent_m})


func _process(delta: float) -> void:
	# Skip first 30 frames (warmup); start measuring after
	if _frame_count < 30:
		_frame_count += 1
		return

	var dt_ms: float = delta * 1000.0
	_frame_time_accum += dt_ms
	_frame_time_min = min(_frame_time_min, dt_ms)
	_frame_time_max = max(_frame_time_max, dt_ms)
	_frame_count += 1

	if (_frame_count - _last_log_frame) >= frame_log_interval:
		var measured_frames := _frame_count - _last_log_frame
		var avg_ms: float = _frame_time_accum / measured_frames
		var fps: float = 1000.0 / avg_ms if avg_ms > 0 else 0.0
		Log.info("clipmap_proto",
			"perf",
			{
				"frames": _frame_count,
				"avg_ms": "%.2f" % avg_ms,
				"min_ms": "%.2f" % _frame_time_min,
				"max_ms": "%.2f" % _frame_time_max,
				"fps": "%.0f" % fps,
			})
		# Reset window
		_frame_time_accum = 0.0
		_frame_time_min = 1e9
		_frame_time_max = 0.0
		_last_log_frame = _frame_count


func _build_mesh() -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)

	var vertex_count := grid_n * grid_n
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	verts.resize(vertex_count)
	uvs.resize(vertex_count)
	normals.resize(vertex_count)

	var cell_size := world_extent_m / float(grid_n - 1)
	var origin := -world_extent_m * 0.5

	for iz in range(grid_n):
		for ix in range(grid_n):
			var idx := iz * grid_n + ix
			var x := origin + ix * cell_size
			var z := origin + iz * cell_size
			verts[idx] = Vector3(x, 0.0, z)
			uvs[idx] = Vector2(
				float(ix) / float(grid_n - 1),
				float(iz) / float(grid_n - 1)
			)
			normals[idx] = Vector3.UP  # placeholder; shader displaces

	# Triangle indices: 2 tris per cell, (grid_n-1)^2 cells
	var indices := PackedInt32Array()
	var index_count := (grid_n - 1) * (grid_n - 1) * 6
	indices.resize(index_count)
	var i := 0
	for iz in range(grid_n - 1):
		for ix in range(grid_n - 1):
			var tl := iz * grid_n + ix
			var tr := tl + 1
			var bl := tl + grid_n
			var br := bl + 1
			# Tri 1: top-left, bottom-left, top-right
			indices[i] = tl; i += 1
			indices[i] = bl; i += 1
			indices[i] = tr; i += 1
			# Tri 2: top-right, bottom-left, bottom-right
			indices[i] = tr; i += 1
			indices[i] = bl; i += 1
			indices[i] = br; i += 1

	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var shader_path := "res://addons/world5/examples/renderer_research_prototype/minimal_clipmap.gdshader"
	var shader: Shader = load(shader_path)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if heightmap_texture != null:
		mat.set_shader_parameter("heightmap", heightmap_texture)
	mat.set_shader_parameter("height_scale", height_scale_m)
	mat.set_shader_parameter("extent_m", world_extent_m)

	mesh.surface_set_material(0, mat)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	add_child(_mesh_instance)

	Log.info("clipmap_proto",
		"mesh built",
		{"verts": vertex_count, "tris": index_count / 3})
