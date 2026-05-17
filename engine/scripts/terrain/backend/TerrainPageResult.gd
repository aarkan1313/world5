## TerrainPageResult — result shape from the terrain backend.
##
## Per spec 20 page contract. Populated fields correspond to the
## request.capabilities list. `has_capability(name)` reports whether
## the result has data for a specific capability; `is_complete()`
## checks every requested capability is populated.
##
## GPU fields are Texture2DRD / Texture2DArrayRD; CPU fields are
## PackedFloat32Array / PackedByteArray. Both can coexist in a single
## result when the consumer asked for both.

class_name TerrainPageResult extends RefCounted


var request: TerrainPageRequest = null

# GPU-resident (rendering)
var height_gpu: RID = RID()                       # Texture2DRD height page
var biome_mask_gpu: RID = RID()                   # Texture2DArrayRD per-biome
var drainage_map: RID = RID()                     # Texture2DRD (erosion auxiliary)

# CPU-resident (gameplay: collision, nav, decoration, AI)
var height_cpu: PackedFloat32Array = PackedFloat32Array()
var collision_height: PackedFloat32Array = PackedFloat32Array()
var slope: PackedFloat32Array = PackedFloat32Array()
var nav_traversability: PackedByteArray = PackedByteArray()
var biome_mask_cpu: PackedByteArray = PackedByteArray()
var flow_direction: PackedFloat32Array = PackedFloat32Array()  # erosion auxiliary

# Provenance
var cache_key: String = ""                         # spec 12 content-addressed
var version_stamp: Dictionary = {}                 # spec 17 (backend, kernel versions, etc.)


## Returns true iff this result has data for the named capability.
func has_capability(capability: String) -> bool:
	match capability:
		"height_gpu":
			return height_gpu.is_valid()
		"height_cpu":
			return not height_cpu.is_empty()
		"collision_height":
			return not collision_height.is_empty()
		"slope":
			return not slope.is_empty()
		"nav_traversability":
			return not nav_traversability.is_empty()
		"biome_mask_gpu":
			return biome_mask_gpu.is_valid()
		"biome_mask_cpu":
			return not biome_mask_cpu.is_empty()
		"drainage_map":
			return drainage_map.is_valid()
		"flow_direction":
			return not flow_direction.is_empty()
		_:
			return false


## Returns true iff every requested capability is populated AND no
## error was recorded. Empty capability list is "not complete" since
## a no-op result is not a complete one.
func is_complete() -> bool:
	if request == null:
		return false
	if version_stamp.has("error"):
		return false
	if request.capabilities.is_empty():
		return false
	for cap in request.capabilities:
		if not has_capability(cap):
			return false
	return true
