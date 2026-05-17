## DetailArray — per-biome detail overlay manifest (spec 24 Layer 2).
##
## Loads + validates detail_array.json. Companion to MaterialVariants
## (Layer 1). Texture assembly into a Texture2DArray happens in
## DetailTextureArray; this class is the pure-data manifest.
##
## Schema:
##   {
##     "_schema_version": 1,
##     "biome": "<biome_name>",
##     "detail_tiles": ["wet", "moss", "grunge", ...],
##     "slot_blends": {
##       "<slot>": { "<tile>": <weight 0..1>, ... },
##       ...
##     }
##   }
##
## detail_tiles is the ordered list — index in this array = layer index
## in the Texture2DArray. slot_blends maps slot → tile → blend weight
## (0..1). Validator enforces tile references resolve + weights in range.

class_name DetailArray extends RefCounted


var biome: String = ""
var detail_tiles: Array = []                # Array of String
var slot_blends: Dictionary = {}            # Dict[slot] -> Dict[tile] -> float


static func from_file(path: String) -> DetailArray:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return _from_dict(parsed)


static func _from_dict(d: Dictionary) -> DetailArray:
	var da: DetailArray = DetailArray.new()
	da.biome = String(d.get("biome", ""))
	if d.has("detail_tiles") and d["detail_tiles"] is Array:
		for t in d["detail_tiles"]:
			da.detail_tiles.append(String(t))
	if d.has("slot_blends") and d["slot_blends"] is Dictionary:
		da.slot_blends = d["slot_blends"]
	return da


func tile_count() -> int:
	return detail_tiles.size()


func index_of(tile: String) -> int:
	return detail_tiles.find(tile)


## Returns the per-tile weight Dictionary for a slot, or {} if unknown.
func weights_for(slot: String) -> Dictionary:
	if not slot_blends.has(slot):
		return {}
	var d: Variant = slot_blends[slot]
	if not (d is Dictionary):
		return {}
	return d


## Returns Array of error strings; empty = valid.
func validate() -> Array:
	var errors: Array = []
	# tile names that appear in detail_tiles list (for ref-check)
	var known: Dictionary = {}
	for t in detail_tiles:
		known[t] = true
	# Every slot blend must reference only known tiles + weights in range
	for slot in slot_blends.keys():
		var weights_raw: Variant = slot_blends[slot]
		if not (weights_raw is Dictionary):
			errors.append("slot '%s' blends entry is not a Dictionary" % slot)
			continue
		var weights: Dictionary = weights_raw
		for tile in weights.keys():
			if not known.has(tile):
				errors.append("slot '%s' blends weight for unknown tile '%s' (not in detail_tiles)"
					% [slot, tile])
			var w: float = float(weights[tile])
			if w < 0.0 or w > 1.0:
				errors.append("slot '%s' tile '%s' weight %f out of [0,1]"
					% [slot, tile, w])
	return errors
