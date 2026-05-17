## SiblingTextureArray — assembles the runtime Texture2DArray + per-slot
## (start, count) window table from a MaterialVariants manifest +
## on-disk PBR images.
##
## Per spec 24 Layer 1 + spec 25. Phase 5.5 shader binder
## (MaterialPipeline.bind_sibling_array) consumes the texture this
## class produces.
##
## Path convention (per spec 24 + plan 25 schema): each variant's
## `source` field is a path relative to that slot's biome dir, NOT to
## materials/. Resolved as:
##   materials/biome_<biome>/<source>/<map>.png
## So `"source": "ground"` for biome=alpine resolves to
## `materials/biome_alpine/ground/<map>.png` (base texture), and
## `"source": "ground_variants/v0_firn"` resolves to
## `materials/biome_alpine/ground_variants/v0_firn/<map>.png`.
##
## Failure modes (logged, not raised — preflight catches at world load):
##   - missing file → skip variant
##   - mismatched size relative to first loaded variant → skip variant
##   - load error → skip variant
##
## An empty input manifest produces an empty Texture2DArray + empty
## windows. Legitimate during pre-Phase-5.4 walking demo.

class_name SiblingTextureArray extends RefCounted


# The assembled texture. Empty when no variants resolved.
var texture: Texture2DArray = null
# Total layers in `texture` (== sum of slot counts).
var _layer_count: int = 0
# Array of Dictionary{biome, slot, start, count} in concatenation order.
var slot_windows: Array = []


func layer_count() -> int:
	return _layer_count


## Return {start: int, count: int} for a (biome, slot) pair.
## Unknown pair returns {start: 0, count: 0} so shader binders fall
## through to the unbound path without special-casing.
func window_for(biome: String, slot: String) -> Dictionary:
	for w in slot_windows:
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w
		if wd.get("biome", "") == biome and wd.get("slot", "") == slot:
			return {"start": wd.get("start", 0), "count": wd.get("count", 0)}
	return {"start": 0, "count": 0}


## Build a SiblingTextureArray from the manifest + materials root.
## materials_root is the absolute path (or `res://...` / `user://...`)
## of the world bundle's materials/ dir. Per spec 24, each variant's
## `source` is biome-relative; resolution adds the `biome_<biome>/`
## prefix automatically.
## map is the PBR map name (e.g. "albedo", "normal", "roughness").
static func build(manifest: MaterialVariants, materials_root: String,
		map: String) -> SiblingTextureArray:
	var sta: SiblingTextureArray = SiblingTextureArray.new()
	if manifest == null:
		return sta
	var images: Array = []
	var expected_size: Vector2i = Vector2i.ZERO
	for slot_entry in manifest.slots:
		if not (slot_entry is Dictionary):
			continue
		var se: Dictionary = slot_entry
		var biome: String = String(se.get("biome", ""))
		var slot: String = String(se.get("slot", ""))
		var variants: Array = se.get("variants", [])
		var start: int = images.size()
		var count: int = 0
		for v in variants:
			if not (v is Dictionary):
				continue
			var vd: Dictionary = v
			var source: String = String(vd.get("source", ""))
			if source == "":
				continue
			var img_path: String = "%s/biome_%s/%s/%s.png" % [
				materials_root, biome, source, map]
			var img: Image = Image.load_from_file(
				ProjectSettings.globalize_path(img_path))
			if img == null:
				Log.warn("sibling_tex", "image load failed",
					{"path": img_path, "biome": biome, "slot": slot})
				continue
			var sz: Vector2i = img.get_size()
			if expected_size == Vector2i.ZERO:
				expected_size = sz
			elif sz != expected_size:
				Log.warn("sibling_tex", "size mismatch (skipped)",
					{"path": img_path, "got": sz, "want": expected_size})
				continue
			images.append(img)
			count += 1
		if count > 0:
			sta.slot_windows.append({
				"biome": biome,
				"slot": slot,
				"start": start,
				"count": count,
			})
	if images.size() > 0:
		var arr: Texture2DArray = Texture2DArray.new()
		var err: Error = arr.create_from_images(images)
		if err == OK:
			sta.texture = arr
			sta._layer_count = images.size()
		else:
			Log.warn("sibling_tex", "Texture2DArray creation failed",
				{"err": err, "n": images.size()})
	else:
		# Provide an empty placeholder so callers can unconditionally
		# pass `sta.texture` to bind_sibling_array (binder treats
		# null + empty as the unbound case).
		sta.texture = Texture2DArray.new()
	return sta
