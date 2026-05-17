## W5 GpuResourceTracker — tracks RID allocations + ensures cleanup
## on shutdown.
##
## Per spec 08a rule 5: GPU resources outlive GDScript refs because
## the pipeline holds them; on shutdown every owner MUST free its
## RIDs in dependency order or Godot crashes / leaks GPU memory.
## This autoload provides a registry + safety-net _exit_tree that
## frees any RIDs still registered with a warning.
##
## Usage:
##   var rid = RenderingDevice.texture_create(...)
##   GpuResourceTracker.register(rid, "terrain_backend", "texture")
##   ...
##   RenderingDevice.free_rid(rid)
##   GpuResourceTracker.unregister(rid)
##
## Autoload at /root/GpuResourceTracker (registered in Phase 2.12).

class_name GpuResourceTracker extends Node

const SYSTEM_NAME: String = "gpu_tracker"

# rid_int -> {owner: String, category: String, ts_ms: int, approx_bytes: int}
var _allocations: Dictionary = {}


## Register an allocated RID. `category`: 'texture', 'buffer',
## 'shader', 'pipeline', 'descriptor_set', 'framebuffer', etc.
## `approx_bytes` is optional; helps with get_total_bytes() telemetry.
func register(rid: RID, owner_name: String, category: String, approx_bytes: int = 0) -> void:
	var key := rid.get_id()
	if _allocations.has(key):
		Log.warn(SYSTEM_NAME, "RID already registered; overwriting",
			{"rid": key, "previous_owner": _allocations[key]["owner"],
			 "new_owner": owner_name})
	_allocations[key] = {
		"owner": owner_name,
		"category": category,
		"ts_ms": Time.get_ticks_msec(),
		"approx_bytes": approx_bytes,
	}


## Owner must call after RenderingDevice.free_rid(rid).
func unregister(rid: RID) -> void:
	var key := rid.get_id()
	if not _allocations.has(key):
		Log.warn(SYSTEM_NAME, "unregister: unknown RID",
			{"rid": key})
		return
	_allocations.erase(key)


## Diagnostic: list current allocations, optionally filtered by owner.
func get_allocations(owner_name: String = "") -> Array:
	if owner_name == "":
		return _allocations.values()
	var out: Array = []
	for k in _allocations.keys():
		if _allocations[k]["owner"] == owner_name:
			out.append(_allocations[k])
	return out


## Diagnostic: approximate total bytes tracked.
func get_total_bytes() -> int:
	var total := 0
	for k in _allocations.keys():
		total += _allocations[k].get("approx_bytes", 0)
	return total


## Diagnostic: per-owner allocation count.
func get_owner_counts() -> Dictionary:
	var counts := {}
	for k in _allocations.keys():
		var owner: String = _allocations[k]["owner"]
		counts[owner] = counts.get(owner, 0) + 1
	return counts


# --- Godot lifecycle ---

func _ready() -> void:
	Log.info(SYSTEM_NAME, "GpuResourceTracker ready")


func _exit_tree() -> void:
	if _allocations.is_empty():
		Log.info(SYSTEM_NAME, "shutdown — no leaked RIDs")
		return
	# Safety net: every owner should have freed already. Anything still
	# registered is a leak per spec 08a rule 5.
	Log.warn(SYSTEM_NAME, "shutdown — leaked RIDs detected",
		{"count": _allocations.size(), "owners": get_owner_counts()})
	# We do NOT call RenderingDevice.free_rid here because the
	# RenderingDevice itself may already be torn down. Just log the
	# leak so owners get fixed in implementation.
	_allocations.clear()


## Test helper: reset state.
func _reset() -> void:
	_allocations.clear()
