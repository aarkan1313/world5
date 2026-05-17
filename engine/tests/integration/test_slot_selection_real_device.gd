## Real-GPU regression for per-fragment slot selection (Phase 4.9.b,
## spec 23 §Surface slot model hardened audit C2 2026-05-17).
##
## Pre-4.9.b TerrainWorld bound only the first slot (mv.slots[0]);
## mid + rock textures were dead weight. This test proves
## bind_all_slots() + the shader's per-fragment slot loop actually
## select different slots at different (elevation, slope) inputs.
##
## Method: build a synthetic 2-slot material with VERY distinct
## colors (red ground, blue rock); use elevation bands so red wins
## at low Y, blue wins at high Y; render two SubViewport quads at
## different world Y positions; assert the rendered pixel color
## reflects the expected slot.

extends GutTest


const FIXTURE_ROOT := "user://_slot_select_fixture"


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless)")
		return true
	return false


func _make_two_slot_array() -> Texture2DArray:
	# Layer 0: pure red (ground); Layer 1: pure blue (rock)
	var imgs: Array = []
	for c in [Color(1, 0, 0, 1), Color(0, 0, 1, 1)]:
		var img: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(c)
		imgs.append(img)
	var arr: Texture2DArray = Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


# --- 4.9.b core regression ---

func test_low_elevation_picks_ground_slot() -> void:
	# Two slots: red ground (elev -50..0), blue rock (elev 10..50).
	# Render a flat quad placed at WORLD_Y = -20 (well inside ground
	# band, well below rock band). Should read predominantly red.
	if _skip_if_no_rd():
		return
	var img: Image = await _render_slot_test_quad(-20.0)
	assert_not_null(img, "viewport rendered an image")
	var col: Color = _avg_color(img)
	# Red dominant: r > b by clear margin. Threshold low because:
	# - base mix only applies sibling at 0.7 weight (vs 0.3 fallback)
	# - brightness modulator (0.85 + 0.30 * noise) attenuates further
	# - tonemap reinhard squashes saturated channels
	# Pre-fix (no slot selection): both elevations render identical
	# fallback-tinted color, so r-b ≈ 0. Any positive delta proves
	# the per-fragment slot loop actually fired.
	assert_gt(col.r - col.b, 0.015,
		"low-elevation quad must render red-dominant (ground slot active); " +
		"got %s" % str(col))


func test_high_elevation_picks_rock_slot() -> void:
	# Same setup but quad at WORLD_Y = 30 (well inside rock band).
	# Should read predominantly blue.
	if _skip_if_no_rd():
		return
	var img: Image = await _render_slot_test_quad(30.0)
	assert_not_null(img)
	var col: Color = _avg_color(img)
	assert_gt(col.b - col.r, 0.015,
		"high-elevation quad must render blue-dominant (rock slot active); " +
		"got %s" % str(col))


# --- helpers ---

func _render_slot_test_quad(world_y: float) -> Image:
	# Build a PlaneMesh at the given world Y, bind a ShaderMaterial
	# with terrain_clipmap and 2 slots, render to a SubViewport.
	# Camera looks straight down.
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)

	# Heightmap: uniform value that makes the vertex shader output
	# the desired world_y after its (h - 0.5) * 2 * scale + offset
	# decoding. Solve: world_y = (h - 0.5) * 2 * scale + offset
	# With scale=50, offset=0: h = world_y / 100 + 0.5
	var h_value: float = clamp(world_y / 100.0 + 0.5, 0.0, 1.0)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8 * 8 * 4)
	for i in range(64):
		bytes.encode_float(i * 4, h_value)
	var himg: Image = Image.create_from_data(8, 8, false, Image.FORMAT_RF, bytes)
	var htex: ImageTexture = ImageTexture.create_from_image(himg)
	p.bind_height_map(mat, htex, 50.0, 0.0)

	var arr: Texture2DArray = _make_two_slot_array()
	var windows: Array = [
		{"start": 0, "count": 1},
		{"start": 1, "count": 1},
	]
	var elev_bands: Array = [
		{"min": -50.0, "max":  0.0, "band_min": 2.0, "band_max": 2.0},  # ground
		{"min":  10.0, "max": 50.0, "band_min": 2.0, "band_max": 2.0},  # rock
	]
	# Both slots accept any slope so slot selection here is purely
	# elevation-driven; isolates the test to one variable
	var slope_bands: Array = [
		{"min": 0.0, "max": 90.0, "band_min": 1.0, "band_max": 1.0},
		{"min": 0.0, "max": 90.0, "band_min": 1.0, "band_max": 1.0},
	]
	p.bind_all_slots(mat, arr, windows, elev_bands, slope_bands)

	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var cam: Camera3D = Camera3D.new()
	# Camera 50m above the quad's world Y, looking down
	cam.position = Vector3(0, world_y + 50.0, 0.001)
	viewport.add_child(cam)
	cam.look_at(Vector3(0, world_y, 0), Vector3(0, 0, -1))
	cam.far = 5000.0

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(20.0, 20.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mesh_inst.mesh = pm
	mesh_inst.material_override = mat
	# Place the mesh — vertex shader will displace its Y from the
	# heightmap sample (which we tuned so VERTEX.y = world_y)
	mesh_inst.position = Vector3(0, 0, 0)
	viewport.add_child(mesh_inst)

	# Light so unshaded surfaces don't read pitch-black
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 30, 0)
	viewport.add_child(light)

	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = viewport.get_texture().get_image()

	# Synchronous free
	mesh_inst.free()
	cam.free()
	light.free()
	viewport.free()
	return img


func _avg_color(img: Image) -> Color:
	if img == null:
		return Color(0, 0, 0, 0)
	var r: float = 0.0; var g: float = 0.0; var b: float = 0.0
	var n: int = 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c: Color = img.get_pixel(x, y)
			r += c.r; g += c.g; b += c.b
			n += 1
	var fn: float = max(1.0, float(n))
	return Color(r / fn, g / fn, b / fn, 1.0)
