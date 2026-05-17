## MaterialVariants — loads the per-world material_variants.json
## sibling manifest (spec 24 Layer 1 contract).
##
## Phase 5 scaffold: reads + validates the manifest schema. The actual
## texture binding into a Texture2DArray happens when the texture
## pipeline produces real sibling sets (Phase 5.4+) and the runtime
## variety shader (Phase 5.5) consumes them. Until then this class
## just holds the parsed manifest for inspection.

class_name MaterialVariants extends RefCounted


# Parsed manifest fields (mirrors material_variants.json schema)
var world_seed: int = 0
var region_size_m: float = 0.0
var edge_blend_m: float = 0.0
var max_variants_per_slot: int = 8
var max_total_variant_layers: int = 256
# Array of Dictionary{biome, slot, variants: Array of {id, source, weight}}
var slots: Array = []


static func from_file(path: String) -> MaterialVariants:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return _from_dict(parsed)


static func _from_dict(d: Dictionary) -> MaterialVariants:
	var mv: MaterialVariants = MaterialVariants.new()
	mv.world_seed = int(d.get("world_seed", 0))
	mv.region_size_m = float(d.get("region_size_m", 0.0))
	mv.edge_blend_m = float(d.get("edge_blend_m", 0.0))
	mv.max_variants_per_slot = int(d.get("max_variants_per_slot", 8))
	mv.max_total_variant_layers = int(d.get("max_total_variant_layers", 256))
	if d.has("slots") and d["slots"] is Array:
		mv.slots = d["slots"]
	return mv


## Returns Array of error strings; empty = valid (per spec 24 validation
## rules). Used by world contract preflight.
func validate() -> Array:
	var errors: Array = []
	if region_size_m <= 0.0:
		errors.append("region_size_m must be > 0 (got %f)" % region_size_m)
	if edge_blend_m >= region_size_m / 4.0:
		errors.append("edge_blend_m (%f) must be < region_size_m/4 (%f)" % [
			edge_blend_m, region_size_m / 4.0])
	if max_variants_per_slot > 8:
		errors.append("max_variants_per_slot capped at 8 (shader limit); got %d"
			% max_variants_per_slot)

	var total_layers: int = 0
	for s in slots:
		if not (s is Dictionary):
			errors.append("slot entry not a Dictionary")
			continue
		var slot_d: Dictionary = s
		var variants: Array = slot_d.get("variants", [])
		if variants.size() > max_variants_per_slot:
			errors.append("slot '%s/%s' has %d variants > cap %d" % [
				slot_d.get("biome", "?"), slot_d.get("slot", "?"),
				variants.size(), max_variants_per_slot])
		total_layers += variants.size()
	if total_layers > max_total_variant_layers:
		errors.append("total variant layers %d > cap %d" % [
			total_layers, max_total_variant_layers])
	return errors


## Returns the variants array for a specific (biome, slot), or empty.
func variants_for(biome: String, slot: String) -> Array:
	for s in slots:
		if not (s is Dictionary):
			continue
		var slot_d: Dictionary = s
		if slot_d.get("biome", "") == biome and slot_d.get("slot", "") == slot:
			return slot_d.get("variants", [])
	return []


## Total bound layers across all slots (for shader-cap accounting).
func total_variant_layers() -> int:
	var n: int = 0
	for s in slots:
		if s is Dictionary:
			n += (s as Dictionary).get("variants", []).size()
	return n
