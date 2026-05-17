## RingDebugOverlay — toggleable per-ring wireframe + bounds visual.
##
## Per spec 21 module decomposition. Stays off by default; toggle via
## TerrainWorld.debug_overlay or directly via set_enabled(). Each ring
## gets a wireframe overlay child so the player can see ring footprint
## + LOD boundaries when debugging.

class_name RingDebugOverlay extends Node3D


var _enabled: bool = false
var _bound_rings: Array = []     # Array[ClipmapRing] — kept for lazy build
var _ring_visuals: Array = []   # Array[MeshInstance3D] — built on first enable


func _ready() -> void:
	visible = _enabled


## Bind to a list of ClipmapRings. Visuals are NOT built until enabled
## (cheaper when debug_overlay stays off — the default).
func bind_rings(rings: Array) -> void:
	_bound_rings = rings.duplicate()
	if _enabled:
		_rebuild_visuals()


func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	if on and _ring_visuals.is_empty() and not _bound_rings.is_empty():
		_rebuild_visuals()


func is_enabled() -> bool:
	return _enabled


func _rebuild_visuals() -> void:
	# Clear previous visuals (use free() to drop RIDs immediately so
	# scene teardown doesn't leak; queue_free was leaving them
	# pending across exit).
	for v in _ring_visuals:
		if is_instance_valid(v):
			v.free()
	_ring_visuals.clear()
	for ring in _bound_rings:
		var visual: MeshInstance3D = _make_ring_visual(ring)
		add_child(visual)
		_ring_visuals.append(visual)


# --- internal ---

func _make_ring_visual(ring: ClipmapRing) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "RingOverlay_L%d" % ring.level
	# Simple box mesh sized to the ring's local AABB; the ring's
	# MeshInstance3D translation moves it with the camera.
	var aabb: AABB = AABB()
	if ring.mesh_instance.mesh != null:
		aabb = ring.mesh_instance.mesh.get_aabb()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(aabb.size.x, 1.0, aabb.size.z)  # thin slab
	mi.mesh = box
	# Wireframe via unshaded material with a per-level tint
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var hue: float = float(ring.level) * 0.18
	mat.albedo_color = Color.from_hsv(fmod(hue, 1.0), 0.85, 1.0, 0.18)
	mi.material_override = mat
	# Track the ring's position each frame via a callable
	mi.set_meta("ring_ref", ring)
	return mi


func _process(_delta: float) -> void:
	if not _enabled:
		return
	# Follow each ring's position so the overlay tracks camera-snap
	for v in _ring_visuals:
		if not is_instance_valid(v):
			continue
		var ring: ClipmapRing = v.get_meta("ring_ref")
		if ring != null and ring.mesh_instance != null:
			v.position = ring.mesh_instance.position
