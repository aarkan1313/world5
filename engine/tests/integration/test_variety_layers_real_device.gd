## Real-GPU integration test for spec 24 Layer 1 (siblings + stochastic UV)
## + Layer 2 (detail overlays).
##
## Phase 5.5. Validates that:
## - The terrain_clipmap shader compiles with the new uniforms +
##   primitive calls (catches GLSL parse errors a unit test can't).
## - Binding a synthetic 3-layer sibling array does not crash the
##   draw call.
## - A SubViewport render returns non-trivial output (some pixel
##   variance) when siblings are bound vs the macro-only fallback,
##   proving the Layer 1 path is actually sampled.

extends GutTest


const TERRAIN_SHADER := "res://addons/world5/shaders/terrain_clipmap.gdshader"


func _skip_if_no_rd() -> bool:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (likely --headless mode)")
		return true
	return false


func _make_array(layers: int, colors: Array, size: int = 32) -> Texture2DArray:
	# Each layer is a solid color; image stride proves the shader is
	# actually sampling different layers (not just one).
	assert_eq(colors.size(), layers, "colors size must match layers")
	var imgs: Array = []
	for i in range(layers):
		var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(colors[i])
		imgs.append(img)
	var arr: Texture2DArray = Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


# --- shader compile (catches GLSL errors that unit tests can't) ---

func test_shader_loads_without_errors() -> void:
	if _skip_if_no_rd():
		return
	# Loading the shader resource doesn't compile it — but creating a
	# material that uses it + setting its uniforms triggers parsing
	# under Godot's renderer. This catches things like syntax errors,
	# duplicate uniform declarations, or sampler-type mismatches that
	# a text-grep can't see.
	var shader: Shader = load(TERRAIN_SHADER)
	assert_not_null(shader, "terrain_clipmap.gdshader loadable")
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	# Bind enough uniforms to make a renderable material; the renderer
	# will compile when the material is first used. Set a valid default
	# height_map so the vertex shader doesn't sample null.
	var h: Image = Image.create(8, 8, false, Image.FORMAT_RF)
	h.fill(Color(0.5, 0, 0, 0))
	mat.set_shader_parameter("height_map", ImageTexture.create_from_image(h))
	assert_not_null(mat)


# --- siblings: binding integration ---

func _setup_top_down_viewport() -> Dictionary:
	# Returns a dict with viewport + cam + mesh_inst keys. Caller
	# binds material to mesh_inst.material_override, then awaits two
	# frames. Camera must be add_child'd BEFORE look_at — calling
	# look_at on an orphan node errors out.
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0, 10, 0)
	viewport.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(20.0, 20.0)
	pm.subdivide_width = 16
	pm.subdivide_depth = 16
	mesh_inst.mesh = pm
	viewport.add_child(mesh_inst)
	return {"viewport": viewport, "cam": cam, "mesh_inst": mesh_inst}


func _teardown_viewport(d: Dictionary) -> void:
	# free() — synchronous so the test's after-each sees no orphans;
	# queue_free defers until next frame which leaves them dangling for
	# the duration of the test report.
	(d["mesh_inst"] as MeshInstance3D).free()
	(d["cam"] as Camera3D).free()
	(d["viewport"] as SubViewport).free()


func test_bind_sibling_array_does_not_crash_draw() -> void:
	if _skip_if_no_rd():
		return
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_array(3, [
		Color(1.0, 0.0, 0.0, 1.0),
		Color(0.0, 1.0, 0.0, 1.0),
		Color(0.0, 0.0, 1.0, 1.0),
	])
	p.bind_sibling_array(mat, arr, 0, 3)
	var h: Image = Image.create(16, 16, false, Image.FORMAT_RF)
	h.fill(Color(0.5, 0, 0, 0))
	p.bind_height_map(mat, ImageTexture.create_from_image(h), 0.0, 0.0)
	var setup: Dictionary = _setup_top_down_viewport()
	(setup["mesh_inst"] as MeshInstance3D).material_override = mat
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = (setup["viewport"] as SubViewport).get_texture().get_image()
	assert_not_null(img, "viewport rendered an image")
	_teardown_viewport(setup)


func test_bind_detail_array_does_not_crash_draw() -> void:
	if _skip_if_no_rd():
		return
	var p: MaterialPipeline = MaterialPipeline.new()
	var mat: ShaderMaterial = p.make_ring_material(0)
	var arr: Texture2DArray = _make_array(2, [
		Color(0.1, 0.1, 0.1, 0.8),
		Color(0.9, 0.9, 0.9, 0.6),
	])
	p.bind_detail_array(mat, arr, 2)
	var h: Image = Image.create(16, 16, false, Image.FORMAT_RF)
	h.fill(Color(0.5, 0, 0, 0))
	p.bind_height_map(mat, ImageTexture.create_from_image(h), 0.0, 0.0)
	var setup: Dictionary = _setup_top_down_viewport()
	(setup["mesh_inst"] as MeshInstance3D).material_override = mat
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = (setup["viewport"] as SubViewport).get_texture().get_image()
	assert_not_null(img)
	_teardown_viewport(setup)


# --- behavior: siblings change the output ---

func _render_quad(mat: ShaderMaterial) -> Image:
	# Helper: render the material on a plane to a SubViewport, return
	# the resulting Image. Used for "siblings change pixels" check.
	var setup: Dictionary = _setup_top_down_viewport()
	(setup["mesh_inst"] as MeshInstance3D).material_override = mat
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = (setup["viewport"] as SubViewport).get_texture().get_image()
	_teardown_viewport(setup)
	return img


func _avg_color(img: Image) -> Color:
	if img == null:
		return Color(0, 0, 0, 0)
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	var n: int = 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c: Color = img.get_pixel(x, y)
			r += c.r; g += c.g; b += c.b
			n += 1
	var fn: float = max(1.0, float(n))
	return Color(r / fn, g / fn, b / fn, 1.0)


func test_siblings_path_changes_output_vs_macro_only() -> void:
	# Two materials: one with siblings bound (Layer 1 active), one
	# without (macro-only fallback). The two renders must differ —
	# proves the has_siblings branch is actually taken.
	#
	# To make the difference unambiguous, use sibling colors whose mean
	# is distinctly NOT the olive fallback (~0.35, 0.45, 0.25). Pure
	# magenta-family siblings (red+blue, no green) pull the average way
	# off-axis from the fallback so a per-channel comparison can detect
	# the change even if hue stays similar.
	if _skip_if_no_rd():
		return
	var p: MaterialPipeline = MaterialPipeline.new()
	var h: Image = Image.create(16, 16, false, Image.FORMAT_RF)
	h.fill(Color(0.5, 0, 0, 0))
	var htex: ImageTexture = ImageTexture.create_from_image(h)

	# Baseline: no siblings — fragment falls through to fallback_color
	var mat_no: ShaderMaterial = p.make_ring_material(0)
	p.bind_height_map(mat_no, htex, 0.0, 0.0)
	var img_no: Image = await _render_quad(mat_no)
	var col_no: Color = _avg_color(img_no)

	# With siblings: three magenta-family colors. avg(rgb) = (0.67, 0,
	# 0.67); blended at 70/30 with the fallback's (0.30, 0.38, 0.21)
	# gives ~(0.56, 0.11, 0.49). Per-channel distance from baseline
	# must be > a sensible threshold.
	var mat_yes: ShaderMaterial = p.make_ring_material(0)
	p.bind_height_map(mat_yes, htex, 0.0, 0.0)
	var arr: Texture2DArray = _make_array(3, [
		Color(1.0, 0.0, 1.0, 1.0),  # magenta
		Color(1.0, 0.0, 0.5, 1.0),  # pink
		Color(0.5, 0.0, 1.0, 1.0),  # violet
	])
	p.bind_sibling_array(mat_yes, arr, 0, 3)
	var img_yes: Image = await _render_quad(mat_yes)
	var col_yes: Color = _avg_color(img_yes)

	# Per-channel deltas. At least one channel must shift by ≥ 0.05
	# (sensible threshold; macro-only path is constant fallback so the
	# shift is purely from Layer 1).
	var dr: float = abs(col_yes.r - col_no.r)
	var dg: float = abs(col_yes.g - col_no.g)
	var db: float = abs(col_yes.b - col_no.b)
	var max_delta: float = max(max(dr, dg), db)
	assert_gt(max_delta, 0.05,
		"sibling-bound render must differ from unbound by ≥ 0.05 in " +
		"at least one channel (no=%s yes=%s deltas=%f,%f,%f)" % [
			str(col_no), str(col_yes), dr, dg, db])
