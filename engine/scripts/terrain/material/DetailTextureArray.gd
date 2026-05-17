## DetailTextureArray — assembles the runtime Texture2DArray for
## Layer 2 detail overlays from a DetailArray manifest + on-disk
## per-tile PBR overlay images.
##
## Per spec 24 Layer 2 + spec 25. Phase 5.5 binder
## (MaterialPipeline.bind_detail_array) consumes the texture this
## class produces.
##
## Path convention: detail tiles live at
##   materials/biome_<biome>/detail/<tile>_<map>.png
## (single dir, tile name as filename prefix). DetailArray.detail_tiles
## defines the load order; tiles that fail to load are skipped + a
## tile→layer index map preserves caller's ability to look up the
## actual layer in the assembled array.

class_name DetailTextureArray extends RefCounted


var texture: Texture2DArray = null
var _layer_count: int = 0
# Dict[tile_name] -> layer index in `texture`. Built post-load so
# skipped tiles don't shift downstream indices for the caller.
var _tile_to_index: Dictionary = {}


func layer_count() -> int:
	return _layer_count


## Returns the layer index for a tile in the assembled Texture2DArray,
## or -1 if the tile is unknown / failed to load.
func layer_index_of(tile: String) -> int:
	return int(_tile_to_index.get(tile, -1))


## Build a DetailTextureArray from the manifest + materials root.
## materials_root is the absolute/res:// path under which
## `biome_<biome>/detail/<tile>_<map>.png` files live.
static func build(manifest: DetailArray, materials_root: String,
		map: String) -> DetailTextureArray:
	var dta: DetailTextureArray = DetailTextureArray.new()
	if manifest == null:
		return dta
	var images: Array = []
	var expected_size: Vector2i = Vector2i.ZERO
	var biome_dir: String = "biome_%s/detail" % manifest.biome
	for tile in manifest.detail_tiles:
		var tile_name: String = String(tile)
		var img_path: String = "%s/%s/%s_%s.png" % [
			materials_root, biome_dir, tile_name, map]
		var img: Image = Image.load_from_file(
			ProjectSettings.globalize_path(img_path))
		if img == null:
			Log.warn("detail_tex", "image load failed",
				{"path": img_path, "biome": manifest.biome, "tile": tile_name})
			continue
		var sz: Vector2i = img.get_size()
		if expected_size == Vector2i.ZERO:
			expected_size = sz
		elif sz != expected_size:
			Log.warn("detail_tex", "size mismatch (skipped)",
				{"path": img_path, "got": sz, "want": expected_size})
			continue
		dta._tile_to_index[tile_name] = images.size()
		images.append(img)
	if images.size() > 0:
		var arr: Texture2DArray = Texture2DArray.new()
		var err: Error = arr.create_from_images(images)
		if err == OK:
			dta.texture = arr
			dta._layer_count = images.size()
		else:
			Log.warn("detail_tex", "Texture2DArray creation failed",
				{"err": err, "n": images.size()})
	else:
		dta.texture = Texture2DArray.new()
	return dta
