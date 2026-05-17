## One-shot capture helper for agent-side visual review.
## Attached as a child of WalkingDemo via walking_demo_capture.tscn.
##
## Reorients the WalkCamera to look down at the terrain, waits for
## pages to stream, captures the main viewport, saves a PNG, quits.

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
	if cam.has_method("_capture_mouse"):
		cam._capture_mouse(false)
	# Oblique top-down angle so heightmap displacement is visible
	# when textures land in Phase 5.
	cam.position = Vector3(40.0, 70.0, 40.0)
	cam.rotation_degrees = Vector3(-30.0, -45.0, 0.0)
	cam.fov = 75.0
	cam.far = 5000.0


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
			" resident_pages=", resident,
			" full_detail_ready=", full_ready)
	get_tree().quit(0)
