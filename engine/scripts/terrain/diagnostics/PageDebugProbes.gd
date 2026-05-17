## PageDebugProbes — introspection helpers for terrain page state.
##
## Per spec 21 module decomposition. RefCounted; consumers query
## "what page covers world_xz?", "is this page resident?", etc.
## Used by the live editor + by test assertions.

class_name PageDebugProbes extends RefCounted


var _cache: TerrainPageCache = null
var _page_extent_m: float = 256.0


func configure(cache: TerrainPageCache, page_extent_m: float) -> void:
	_cache = cache
	_page_extent_m = page_extent_m


## Returns the page-origin XZ that covers a given world XZ for a
## given ring index. Pages tile world space at page_extent_m
## intervals (origin at multiples of page_extent_m).
func page_origin_for(world_xz: Vector2) -> Vector2:
	return Vector2(
		floor(world_xz.x / _page_extent_m) * _page_extent_m,
		floor(world_xz.y / _page_extent_m) * _page_extent_m,
	)


func is_resident(ring: int, world_xz: Vector2) -> bool:
	if _cache == null:
		return false
	return _cache.has(ring, page_origin_for(world_xz))


## Returns a summary Dictionary of resident page count + total bytes.
## Cheap; safe to call every frame for an HUD overlay.
func summary() -> Dictionary:
	if _cache == null:
		return {"pages": 0, "bytes": 0}
	return {
		"pages": _cache.size(),
		"bytes": _cache.total_bytes(),
	}
