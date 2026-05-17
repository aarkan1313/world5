## ResidencyManager — diffs required pages vs cached pages, emits
## load/evict signals for the streaming layer to act on.
##
## Per spec 21 + plan doc Phase 4.4.b. Consumers call:
##   1. `required_pages_for_ring(camera_xz, ring_index, ring_extent_m)`
##      to compute which page-aligned tiles cover a ring's footprint.
##   2. `update(required)` each frame, where `required` is the combined
##      list across all rings.
##
## The manager tracks last-frame's required set; the diff against
## the cache produces load (missing) + evict (no-longer-required)
## signals. The actual streaming work happens via PageStreamingJob
## reacting to page_load_requested.
##
## This class is purely reactive — it doesn't hold pages itself, and
## doesn't dispatch jobs. The owner (TerrainWorld) wires the signals
## to the job system + cache writeback.
##
## Node (not RefCounted) so it can emit signals.

class_name ResidencyManager extends Node


signal page_load_requested(ring: int, page_xz: Vector2)
signal page_evict_requested(ring: int, page_xz: Vector2)


var _cache: TerrainPageCache = null
var _page_extent_m: float = 256.0    # spec 20 default page extent

# Last-frame's required set, encoded as a Dictionary[key -> {ring, xz}]
# for fast diff.
var _last_required: Dictionary = {}


func configure(cache: TerrainPageCache, page_extent_m: float) -> void:
	_cache = cache
	_page_extent_m = page_extent_m


## Compute the set of page-origin-aligned tiles that cover a ring's
## footprint. Returns Array[Dictionary{"ring": int, "xz": Vector2}].
##
## camera_xz: world camera position (XZ)
## ring_index: ring's LOD level (used as-is in the returned entries)
## ring_extent_m: ring's full world-space side length
func required_pages_for_ring(camera_xz: Vector2, ring_index: int,
		ring_extent_m: float) -> Array:
	var half: float = ring_extent_m * 0.5
	# Snap min corner to page boundary (page origin = world XZ where
	# page covers [origin, origin + page_extent_m))
	var min_xz: Vector2 = camera_xz - Vector2(half, half)
	var max_xz: Vector2 = camera_xz + Vector2(half, half)
	var page0_x: int = int(floor(min_xz.x / _page_extent_m))
	var page0_y: int = int(floor(min_xz.y / _page_extent_m))
	var page1_x: int = int(floor((max_xz.x - 0.001) / _page_extent_m))
	var page1_y: int = int(floor((max_xz.y - 0.001) / _page_extent_m))

	var out: Array = []
	for py in range(page0_y, page1_y + 1):
		for px in range(page0_x, page1_x + 1):
			out.append({
				"ring": ring_index,
				"xz": Vector2(
					float(px) * _page_extent_m,
					float(py) * _page_extent_m,
				),
			})
	return out


## Diff required-this-frame vs cache. Emits page_load_requested for
## each missing required page; emits page_evict_requested for each
## previously-required page that's no longer in the set.
##
## required: Array[Dictionary{"ring": int, "xz": Vector2}]
func update(required: Array) -> void:
	if _cache == null:
		return

	# Build the new required dict for fast lookup
	var new_required: Dictionary = {}
	for entry in required:
		var k: String = _key(entry["ring"], entry["xz"])
		new_required[k] = entry

	# Loads: required this frame, not in cache
	for k in new_required.keys():
		var entry: Dictionary = new_required[k]
		var ring: int = entry["ring"]
		var xz: Vector2 = entry["xz"]
		if not _cache.has(ring, xz):
			page_load_requested.emit(ring, xz)

	# Evicts: required LAST frame, not required this frame
	# (snapshot keys to avoid pitfall meta-3 — iterate during erase)
	var keys_to_check: Array = _last_required.keys()
	for k in keys_to_check:
		if not new_required.has(k):
			var entry: Dictionary = _last_required[k]
			page_evict_requested.emit(entry["ring"], entry["xz"])

	_last_required = new_required


func _key(ring: int, page_xz: Vector2) -> String:
	return "%d:%d:%d" % [ring, int(page_xz.x), int(page_xz.y)]
