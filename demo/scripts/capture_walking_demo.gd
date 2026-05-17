## One-shot capture helper for agent-side visual review.
## Attached as a child of WalkingDemo via walking_demo_capture.tscn.
##
## Reorients the WalkCamera to look DOWN at the terrain (the default
## camera looks horizontally which sees only sky), waits a settle
## period, captures the main viewport, saves a PNG, quits.

extends Node


const SETTLE_SECONDS: float = 8.0
const SHOT_PATH: String = "user://_capture_walking_demo.png"

var _elapsed: float = 0.0
var _captured: bool = false


func _ready() -> void:
	var cam: Camera3D = get_parent().get_node_or_null("WalkCamera") as Camera3D
	if cam == null:
		push_error("WalkCamera not found")
		return
	# Release mouse capture so the test doesn't grab input
	if cam.has_method("_capture_mouse"):
		cam._capture_mouse(false)
	# Reposition + tilt down so we actually look at the terrain.
	# Default WalkCamera sits at (0, 60, 0) looking horizontally.
	# Lower vantage + steep down tilt so the terrain surface clearly
	# fills the frame (Phase 4.6 visual review: tests with
	# horizontal-ish camera show mostly procedural-sky ground band
	# making it ambiguous whether terrain is rendering at all).
	# Top-down "is the terrain there at all?" diagnostic:
	# 200m up, looking straight down. Sky strip should be tiny;
	# terrain should fill ~all of the viewport if it's rendering.
	cam.position = Vector3(0.0, 200.0, 0.0)
	cam.rotation_degrees = Vector3(-89.0, 0.0, 0.0)
	cam.fov = 75.0
	# Lower the camera + tilt at ~45° so the heightmap displacement
	# is clearly visible (top-down hides height variation; oblique
	# shows hills + valleys).
	cam.position = Vector3(40.0, 70.0, 40.0)
	cam.rotation_degrees = Vector3(-30.0, -45.0, 0.0)
	print("CAPTURE_HELPER: camera repositioned to ", cam.position,
		" rot=", cam.rotation_degrees, " fov=", cam.fov)


func _process(delta: float) -> void:
	if _captured:
		return
	_elapsed += delta
	if _elapsed < SETTLE_SECONDS:
		return
	_captured = true

	var tw: Node = get_parent().get_node_or_null("TerrainWorld")
	var resident: int = 0
	var full_ready: bool = false
	if tw != null:
		if tw.has_method("get_resident_pages"):
			resident = tw.get_resident_pages().size()
		if tw.has_method("is_full_detail_ready"):
			full_ready = tw.is_full_detail_ready()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		var err: int = img.save_png(SHOT_PATH)
		print("CAPTURE_HELPER: saved=", err == OK,
			" path=", SHOT_PATH,
			" size=", img.get_width(), "x", img.get_height(),
			" resident_pages=", resident,
			" full_detail_ready=", full_ready)
	else:
		push_error("get_image returned null")
	get_tree().quit(0)
