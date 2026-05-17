## WalkCamera — minimal FPS camera for the walking demo.
##
## WASD = move, mouse = look, Shift = sprint, ESC = release mouse.
## Lives in demo/ not engine/ because it's a demo concern, not an
## engine deliverable; consumer projects use their own camera.

extends Camera3D


@export var walk_speed: float = 8.0
@export var sprint_speed: float = 24.0
@export var mouse_sensitivity: float = 0.002
@export var look_clamp_deg: float = 88.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _mouse_captured: bool = false


func _ready() -> void:
	current = true
	_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		var clamp_rad: float = deg_to_rad(look_clamp_deg)
		_pitch = clamp(_pitch, -clamp_rad, clamp_rad)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_capture_mouse(false)
		elif event.keycode == KEY_TAB:
			_capture_mouse(not _mouse_captured)
	elif event is InputEventMouseButton and event.pressed:
		if not _mouse_captured:
			_capture_mouse(true)


func _process(delta: float) -> void:
	if not _mouse_captured:
		return
	var input_dir: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	if Input.is_key_pressed(KEY_SPACE): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL): input_dir.y -= 1.0
	if input_dir == Vector3.ZERO:
		return
	input_dir = input_dir.normalized()
	var speed: float = sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	# Move relative to yaw only (no pitch — typical FPS feel)
	var basis_yaw: Basis = Basis(Vector3.UP, _yaw)
	global_position += basis_yaw * input_dir * speed * delta


func _capture_mouse(on: bool) -> void:
	_mouse_captured = on
	Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if on
		else Input.MOUSE_MODE_VISIBLE)
