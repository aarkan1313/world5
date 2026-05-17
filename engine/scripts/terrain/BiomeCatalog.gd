## BiomeCatalog — per-world biome manifest (spec 22).
##
## Loads + validates biome_catalog.json. The catalog is the source of
## truth for biome assignment, per-biome kernel config, material kit
## reference, per-slot selectors, and climate defaults.
##
## Per-fragment slot selection (spec 23 §Surface slot model, hardened
## Phase 4.9.b 2026-05-17) reads slot selectors from here: each slot
## declares `elevation_m: [min, max]` + `slope_deg: [min, max]` +
## `band_width_*` for smoothstep crossfades. TerrainWorld passes these
## to the fragment shader; shader computes per-fragment weight per slot
## and blends sibling textures weighted by it.

class_name BiomeCatalog extends RefCounted


# Spec 23 hard cap (shader)
const MAX_SLOTS_PER_BIOME: int = 8


var world_name: String = ""
var biome_scale_m: float = 0.0
var elevation_range_m: Vector2 = Vector2.ZERO  # min, max
# Array of biome Dictionaries (kept as parsed Dict so consumers can
# read any field without needing per-field accessors)
var biomes: Array = []
var splat_overrides: Array = []


static func from_file(path: String) -> BiomeCatalog:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return _from_dict(parsed)


static func _from_dict(d: Dictionary) -> BiomeCatalog:
	var bc: BiomeCatalog = BiomeCatalog.new()
	bc.world_name = String(d.get("world_name", ""))
	bc.biome_scale_m = float(d.get("biome_scale_m", 0.0))
	if d.has("elevation_range_m") and d["elevation_range_m"] is Array:
		var er: Array = d["elevation_range_m"]
		if er.size() == 2:
			bc.elevation_range_m = Vector2(float(er[0]), float(er[1]))
	if d.has("biomes") and d["biomes"] is Array:
		bc.biomes = d["biomes"]
	if d.has("splat_overrides") and d["splat_overrides"] is Array:
		bc.splat_overrides = d["splat_overrides"]
	return bc


## Returns the biome Dictionary for `name`, or empty Dict if unknown.
func biome_by_name(name: String) -> Dictionary:
	for b in biomes:
		if b is Dictionary and (b as Dictionary).get("name", "") == name:
			return b
	return {}


## Returns Array of error strings; empty = valid.
func validate() -> Array:
	var errors: Array = []
	if biomes.is_empty():
		errors.append("catalog has no biomes")
	for i in range(biomes.size()):
		var b: Variant = biomes[i]
		if not (b is Dictionary):
			errors.append("biome[%d] not a Dictionary" % i)
			continue
		var bd: Dictionary = b
		if not bd.has("name") or String(bd["name"]) == "":
			errors.append("biome[%d] missing name" % i)
		var slots: Array = bd.get("surface_slots", [])
		if slots.size() > MAX_SLOTS_PER_BIOME:
			errors.append("biome '%s' has %d slots > shader cap %d" % [
				bd.get("name", "?"), slots.size(), MAX_SLOTS_PER_BIOME])
	return errors
