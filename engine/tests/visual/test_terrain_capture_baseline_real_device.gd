## Capture-baseline test for the terrain renderer (OA-C2 audit fix).
##
## Spec 06 §capture-based-tests describes full golden-image diff;
## that infrastructure lands in Phase 4.6 (walking demo) when there's
## a real demo scene to diff against. This file is the OA-C2 minimum-
## viable version: it asserts the terrain WOULD render correctly by
## checking heightmap-binding side-effects, NOT by capturing pixels.
##
## Why this is enough to catch the bug OA-C2 was about: the pre-audit
## Phase 4.4 code had streaming → cache → ... → NOTHING. The bug was
## "page lands in cache but never reaches the shader". This test
## catches that by asserting (a) pages reach the cache, (b)
## is_full_detail_ready transitions to true (which fires from
## _on_page_actually_loaded after height bind succeeds), and (c) the
## ring materials have non-null height_map uniforms set.
##
## Real-GPU only; skipped headless.

extends GutTest


var _budget: StreamingBudget
var _scheduler: JobScheduler
var _tracker: GpuResourceTracker
var _tw: TerrainWorld
var _camera: Node3D


func before_each() -> void:
	_budget = StreamingBudget.new()
	_budget.name = "StreamingBudget"
	get_tree().root.add_child(_budget)
	_scheduler = JobScheduler.new()
	_scheduler.name = "JobScheduler"
	get_tree().root.add_child(_scheduler)
	_tracker = GpuResourceTracker.new()
	_tracker.name = "GpuResourceTracker"
	get_tree().root.add_child(_tracker)

	_camera = Node3D.new()
	_camera.name = "Camera"
	get_tree().root.add_child(_camera)

	_tw = TerrainWorld.new()
	_tw.name = "TerrainWorld"
	_tw.ring_count = 2
	_tw.ring_vertex_grid = 32
	_tw.inner_cell_size_m = 1.0
	_tw.page_extent_m = 32.0
	_tw.terrain_pages_max = 16
	_tw.camera_path = NodePath("../Camera")
	get_tree().root.add_child(_tw)


func after_each() -> void:
	if _tw != null and is_instance_valid(_tw):
		_tw.free()
	if _camera != null and is_instance_valid(_camera):
		_camera.free()
	if _scheduler != null and is_instance_valid(_scheduler):
		_scheduler.free()
	if _budget != null and is_instance_valid(_budget):
		_budget.free()
	if _tracker != null and is_instance_valid(_tracker):
		_tracker.free()


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless)")
		return true
	return false


# --- baseline visual gate: heightmap actually reaches the shader ---

func test_pages_stream_into_cache() -> void:
	if _skip_if_no_rd():
		return
	_camera.global_position = Vector3.ZERO
	# Wait for the first page to stream
	var got_pages: bool = false
	for i in range(120):
		await get_tree().process_frame
		if _tw.get_resident_pages().size() > 0:
			got_pages = true
			break
	assert_true(got_pages, "pages stream into cache within 120 frames")


func test_full_detail_ready_fires() -> void:
	# This is the OA-C2 core gate. full_detail_ready emits from
	# _on_page_actually_loaded → which fires from PageStreamingJob
	# after _cache.put → which only happens after generate_page
	# returned a populated TerrainPageResult. If the heightmap binding
	# wire (TerrainWorld._bind_height_to_ring) regresses, the cache
	# would still fill but is_full_detail_ready would never flip if
	# we hardened the bar to "every ring has at least one bound
	# heightmap" (TODO Phase 4.6).
	if _skip_if_no_rd():
		return
	_camera.global_position = Vector3.ZERO
	var ready: bool = false
	for i in range(180):
		await get_tree().process_frame
		if _tw.is_full_detail_ready():
			ready = true
			break
	assert_true(ready, "is_full_detail_ready() flips true within 180 frames")


func test_ring_materials_have_height_bound() -> void:
	# Per OA-C2 + Phase 4.9.a: confirm each ring's height data IS
	# reaching the shader. Pre-4.9.a this checked the legacy `height_map`
	# Texture2D uniform; post-4.9.a we bind a Texture2DArray + flip
	# `has_height_array=true`. Either path means heightmap data is
	# live on the GPU.
	if _skip_if_no_rd():
		return
	_camera.global_position = Vector3.ZERO
	for i in range(180):
		await get_tree().process_frame
		if _tw.is_full_detail_ready():
			break
	# Inner ring covers the camera page so should always have its
	# heightmap bound. Outer rings may not (their center page may
	# differ from the inner one) — that's a known Phase 4.4 limit.
	var inner: Node = _tw.get_node("ClipmapRing_L0")
	if inner == null:
		# Fall back to first MeshInstance3D child of TW
		for c in _tw.get_children():
			if c.name.begins_with("ClipmapRing_"):
				inner = c
				break
	assert_not_null(inner, "inner ring MeshInstance3D exists")
	var mat: ShaderMaterial = (inner as MeshInstance3D).material_override as ShaderMaterial
	assert_not_null(mat, "ring has ShaderMaterial override")
	var has_array: bool = mat.get_shader_parameter("has_height_array") as bool
	if has_array:
		# Phase 4.9.a path: height_array Texture2DArray must be populated
		var array_tex: Variant = mat.get_shader_parameter("height_array")
		assert_true(array_tex is Texture2DArray,
			"inner ring's height_array uniform is a Texture2DArray (got: %s)"
				% str(array_tex))
		assert_gt(int(mat.get_shader_parameter("height_pages_per_side")), 0,
			"height_pages_per_side must be > 0 when has_height_array is true")
	else:
		# Legacy path: single Texture2D
		var height_tex: Variant = mat.get_shader_parameter("height_map")
		assert_true(height_tex is Texture2D,
			"inner ring's height_map uniform is a populated Texture2D (caught: %s)"
				% str(height_tex))


# --- 2026-05-17 brown-band bug class regression guards ---
#
# The shader-state tests above all passed while the walking demo
# rendered as a flat brown band because the rings were getting
# culled before fragment shader ran. Two separate bugs (AABB Y=0
# from un-displaced CPU verts + back-facing triangle winding + no
# normals) compounded. These tests assert the mesh-level fixes that
# prevent recurrence without needing SubViewport pixel capture.

func test_ring_meshinstance_has_nonzero_y_aabb() -> void:
	# Bug: ArrayMesh.custom_aabb is not honored by Godot 4.6 frustum
	# culling — the override has to live on MeshInstance3D. Without
	# it, the un-displaced y=0 CPU verts make culling reject the ring
	# as soon as the vertex shader displaces height_map samples below
	# y=0. Fix lives in ClipmapRing.configure.
	for c in _tw.get_children():
		if not c.name.begins_with("ClipmapRing_"):
			continue
		var mi: MeshInstance3D = c as MeshInstance3D
		var aabb: AABB = mi.custom_aabb
		assert_gt(aabb.size.y, 100.0,
			"%s.custom_aabb.size.y must be > 100m to survive heightmap " +
			"displacement (got %f). If 0, ArrayMesh.custom_aabb regression " +
			"and frustum culling will reject every ring." % [mi.name, aabb.size.y])


func test_ring_mesh_has_upward_normals() -> void:
	# Bug: missing normals + back-facing triangle winding made the
	# terrain mesh invisible from above (back-face culled even when
	# inside the frustum). Fix lives in ClipmapGeometry._build_ring_mesh
	# (Vector3.UP normals + tl,tr,bl + tr,br,bl winding).
	for c in _tw.get_children():
		if not c.name.begins_with("ClipmapRing_"):
			continue
		var mi: MeshInstance3D = c as MeshInstance3D
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		assert_true(normals is PackedVector3Array,
			"%s mesh must have NORMAL array (was: %s)" % [
				mi.name, str(typeof(normals))])
		if normals is PackedVector3Array:
			var n_arr: PackedVector3Array = normals
			assert_gt(n_arr.size(), 0, "%s normals must be non-empty" % mi.name)
			assert_gt(n_arr[0].dot(Vector3.UP), 0.99,
				"%s normals must point up (sample[0]=%s)" % [mi.name, str(n_arr[0])])
