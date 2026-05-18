## One-shot capture helper for agent-side visual review.
## Attached as a child of WalkingDemo via walking_demo_capture.tscn.
##
## Reorients the WalkCamera to a walking-height terrain view, waits for
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
	# Sprint 3 polish: fly-camera high enough to see Mount Hood
	# foothills shape (Cascades excerpt spans ~800m vertically).
	# Terrain_follow disabled. Stand back 3 km from center, height 800m,
	# pitch -25° for a panoramic alpine view.
	cam.set("terrain_follow_enabled", false)
	cam.set("fly_mode", true)
	# Sprint 4a polish: position deep inside DEM bounds at a sensible
	# altitude (not extreme high or low). z=1500 looks north toward
	# DEM center; y=350 puts camera ~150m above typical foothill peaks.
	# Look slightly down to see the foothills shape.
	cam.position = Vector3(0.0, 350.0, 1500.0)
	cam.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	cam.fov = 75.0
	cam.far = 6000.0


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
