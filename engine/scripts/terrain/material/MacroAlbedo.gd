## MacroAlbedo — loads the world-spanning macro albedo texture +
## provides the AABB → UV mapping for far-ring sampling.
##
## Per spec 24 layer 3 (multi-frequency + macro). Far rings sample
## this single low-res texture at world XZ to break per-page tile
## repeat at distance. World-AABB defines the world-XZ rectangle the
## texture spans; sampling uses world_to_uv() to convert.

class_name MacroAlbedo extends RefCounted


var texture: Texture2D = null
var world_min_xz: Vector2 = Vector2.ZERO
var world_max_xz: Vector2 = Vector2.ZERO


## Load both the config (JSON) and the texture it points at. Returns
## true on success.
##
## Expected JSON:
##   {
##     "world_min_xz": [x, z],
##     "world_max_xz": [x, z],
##     "texture": "res://..."
##   }
func load_from_path(config_path: String) -> bool:
	var f: FileAccess = FileAccess.open(config_path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed
	if not (data.has("world_min_xz") and data.has("world_max_xz")
			and data.has("texture")):
		return false
	if not (data["world_min_xz"] is Array and data["world_max_xz"] is Array):
		return false

	world_min_xz = Vector2(
		float(data["world_min_xz"][0]),
		float(data["world_min_xz"][1]),
	)
	world_max_xz = Vector2(
		float(data["world_max_xz"][0]),
		float(data["world_max_xz"][1]),
	)
	# Texture is optional: loaded via ResourceLoader if path is valid.
	# If load fails, leave texture null — fragment shader can fall back
	# to a default color uniform.
	var tex_path: String = String(data["texture"])
	if ResourceLoader.exists(tex_path):
		texture = load(tex_path)
	return true


## Convert a world-XZ position into [0, 1] UV for sampling the macro
## texture. Out-of-AABB returns are clamped at the boundary.
func world_to_uv(world_xz: Vector2) -> Vector2:
	var span: Vector2 = world_max_xz - world_min_xz
	if span.x <= 0.0 or span.y <= 0.0:
		return Vector2.ZERO
	var uv: Vector2 = (world_xz - world_min_xz) / span
	return Vector2(clamp(uv.x, 0.0, 1.0), clamp(uv.y, 0.0, 1.0))


## Packed for shader push: vec4 (min_x, min_z, max_x, max_z) so the
## fragment shader does its own world-to-UV in one fetch.
func uniform_aabb() -> Vector4:
	return Vector4(world_min_xz.x, world_min_xz.y,
		world_max_xz.x, world_max_xz.y)
