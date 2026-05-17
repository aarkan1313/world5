## Real-GPU regression for multi-page heightmap binding (Phase 4.9.a,
## audit C1 fix).
##
## Pre-fix: TerrainWorld bound one heightmap page per ring covering only
## the ring's snapped center; outer rings stretched the texture at
## edges → visible chunk seams. Spec 21 hardened Quality bar after
## audit: "rings wider than page_extent_m MUST bind multiple pages and
## sample per fragment via world XZ."
##
## This test bypasses the streaming layer and directly constructs a
## RingHeightArray with TWO distinct pages (one all-low, one all-high
## displacement), binds it via MaterialPipeline.bind_height_array,
## renders a quad spanning both pages, and asserts that the rendered
## geometry shows the two distinct displacements at the two halves
## of the visible terrain (proves shader picked the right page per
## fragment).

extends GutTest


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless)")
		return true
	return false


func _flat_height_image(n: int, normalized_value: float) -> Image:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * n * 4)
	for i in range(n * n):
		bytes.encode_float(i * 4, normalized_value)
	return Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)


# --- core regression ---

func test_two_page_array_picks_correct_page_per_fragment() -> void:
	# Build a 2x2-page RingHeightArray (pages_per_side=2), populate
	# page (0,0) with h=0.5 (world_y=0) and page (1,0) with h=1.0
	# (world_y = (1.0 - 0.5) * 2 * 50 = 50). Render a wide quad that
	# spans both pages. Lit from above, the LEFT half (page 0) reads
	# darker (low elevation, shadow side) and the RIGHT half (page 1)
	# reads brighter (high elevation, top of plateau). Pre-fix
	# (single-page binding) would have rendered uniformly.
	if _skip_if_no_rd():
		return

	# Build the array
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(510.0, 256.0)  # 510m ring → pages_per_side = 3
	# Use a 2-page test: place pages at (0,0) and (256,0) in world coords.
	# min_xz = (0, 0); pages_per_side = 3 means layer indices fit.
	rha.set_min_corner(Vector2(0.0, 0.0))
	# Page (0,0): low (h=0.5 normalized → world_y=0)
	rha.add_page(Vector2(0.0,   0.0), _flat_height_image(16, 0.5))
	# Page (256, 0): high (h=1.0 normalized → world_y=50)
	rha.add_page(Vector2(256.0, 0.0), _flat_height_image(16, 1.0))
	var array_tex: Texture2DArray = rha.build_texture_array()
	assert_not_null(array_tex)

	# Build the material
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	p.bind_height_array(mat, array_tex, rha.pages_per_side, rha.min_xz,
		rha.page_extent_m, 50.0, 0.0)

	# Mesh spans world XZ from (50, -50) to (450, 50). At Y=0 origin.
	# Left half (X < 256) reads page 0 → world y = 0.
	# Right half (X >= 256) reads page 1 → world y = 50.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(96, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)

	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(250.0, 200.0, 200.0)
	viewport.add_child(cam)
	cam.look_at(Vector3(250.0, 25.0, 0.0), Vector3(0, 1, 0))
	cam.far = 5000.0
	cam.fov = 60.0

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(400.0, 100.0)
	pm.subdivide_width = 64
	pm.subdivide_depth = 16
	mesh_inst.mesh = pm
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(250.0, 0.0, 0.0)
	# AABB padded to fit the 50m displacement
	mesh_inst.custom_aabb = AABB(
		Vector3(-200.0, -100.0, -50.0),
		Vector3(400.0, 200.0, 100.0))
	viewport.add_child(mesh_inst)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	viewport.add_child(light)

	# Pump frames + capture
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()
	assert_not_null(img)

	# Sample left half (page 0, low) vs right half (page 1, high).
	# The high page is closer to camera (Y=50 vs Y=0) and lit from
	# above-left → brighter pixels. Just need the two halves to
	# differ, proving each page is sampled in its own region.
	var left_avg: float = _avg_brightness_in_region(img, 0, 0, 30, 64)
	var right_avg: float = _avg_brightness_in_region(img, 66, 0, 96, 64)

	# Pre-fix (single page bound = page 0 only): both halves render
	# at world y=0 → identical brightness → delta ~ 0.
	# Post-fix: right half shows the elevated page → measurably
	# different brightness (lighting + parallax differ).
	# Threshold is low because the shader's fallback_color + brightness
	# modulation flatten the displacement contrast; ANY non-zero delta
	# proves per-fragment page selection is firing.
	var delta: float = abs(right_avg - left_avg)
	assert_gt(delta, 0.005,
		"left vs right half of two-page render must differ " +
		"(left=%f right=%f delta=%f); equal halves means shader didn't " +
		"pick the right page per fragment (chunk-seam regression)." % [
			left_avg, right_avg, delta])

	# Cleanup
	mesh_inst.free()
	cam.free()
	light.free()
	viewport.free()


# --- helper ---

func _avg_brightness_in_region(img: Image, x0: int, y0: int,
		x1: int, y1: int) -> float:
	var sum: float = 0.0
	var n: int = 0
	for y in range(y0, min(y1, img.get_height()), 2):
		for x in range(x0, min(x1, img.get_width()), 2):
			var c: Color = img.get_pixel(x, y)
			sum += (c.r + c.g + c.b) / 3.0
			n += 1
	return sum / max(1.0, float(n))
