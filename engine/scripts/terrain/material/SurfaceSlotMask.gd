## SurfaceSlotMask — loads surface_slots.json + maps slot names to
## shader-binding indices.
##
## Per spec 21 module decomposition + spec 24 layer 1 (siblings). The
## world bundle's surface_slots.json declares an ordered list of slots
## (grass, rock, snow, etc.), each with N sibling texture paths.
## MaterialPipeline binds those textures into a Texture2DArray; this
## class maps slot names to the array indices.
##
## Phase 4 ships index-only support. Per-fragment slot selection (which
## slot wins at a given XZ) is part of Phase 6 multi-biome work.

class_name SurfaceSlotMask extends RefCounted


# Parallel arrays for O(1) index lookup by both directions
var _slot_names: Array = []                        # name -> index via find()
var _siblings: Array = []                          # Array[Array[String]]


func slot_count() -> int:
	return _slot_names.size()


func index_of(slot_name: String) -> int:
	return _slot_names.find(slot_name)


func name_of(index: int) -> String:
	if index < 0 or index >= _slot_names.size():
		return ""
	return _slot_names[index]


func siblings_for(index: int) -> Array:
	if index < 0 or index >= _siblings.size():
		return []
	return _siblings[index]


## Load from a surface_slots.json. Returns true on success. Failure
## leaves the mask in its prior state.
func load_from_path(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed
	if not data.has("slots") or not (data["slots"] is Array):
		return false

	var names: Array = []
	var sibs: Array = []
	for slot in data["slots"]:
		if not (slot is Dictionary):
			return false
		var s: Dictionary = slot
		if not s.has("name"):
			return false
		names.append(String(s["name"]))
		var sib_list: Array = []
		if s.has("siblings") and s["siblings"] is Array:
			for p in s["siblings"]:
				sib_list.append(String(p))
		sibs.append(sib_list)

	_slot_names = names
	_siblings = sibs
	return true


## Returns Array of error strings; empty = valid.
func validate() -> Array:
	var errors: Array = []
	if _slot_names.is_empty():
		errors.append("surface_slots has no slots")
	for i in range(_siblings.size()):
		if _siblings[i].is_empty():
			errors.append("slot '%s' has no siblings (need >=1)" % _slot_names[i])
	return errors
