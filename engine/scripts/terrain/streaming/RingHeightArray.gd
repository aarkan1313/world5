## RingHeightArray — per-ring stitched-heightmap state for multi-page
## binding.
##
## Phase 4.9.a (audit C1). Pre-fix, TerrainWorld bound one heightmap
## page per ring covering only the ring's center; outer rings whose
## extent exceeded `page_extent_m` stretched the texture at edges and
## produced visible chunk seams. This class maintains the per-ring
## Texture2DArray of all resident pages + the page_coord → array
## layer mapping the shader uses to sample the right page per
## fragment.
##
## Usage:
##   var rha := RingHeightArray.new()
##   rha.configure(ring_extent_m, page_extent_m)
##   rha.set_min_corner(world_min_xz)
##   on page_loaded(page_xz, height_image):
##     rha.add_page(page_xz, height_image)
##     var tex := rha.build_texture_array()
##     MaterialPipeline.bind_height_array(mat, tex, rha.pages_per_side, ...)
##   on page_evicted(page_xz):
##     rha.remove_page(page_xz)
##
## Public state:
##   pages_per_side: max pages per side a ring of `ring_extent_m`
##     could need (conservative, accounts for ring straddling page
##     boundaries)
##   min_xz: world-space corner of the page grid (page (0,0)'s origin).
##     Shader computes layer = (world_y - min.y)/page_extent * pages_per_side +
##     (world_x - min.x)/page_extent. RingHeightArray packs the
##     Texture2DArray layers in this same SPATIAL order so the
##     shader can compute layer index without a lookup table.

class_name RingHeightArray extends RefCounted


var pages_per_side: int = 1
var page_extent_m: float = 256.0
# Min XZ corner of the page grid (page (0,0)'s origin in world space).
# Updated via set_min_corner() when the ring snaps to a new center;
# shader uses this + page_extent to compute per-fragment layer.
var min_xz: Vector2 = Vector2.ZERO
var _ring_extent_m: float = 0.0
# Spatially-indexed images. Key = "px:py" (page coords RELATIVE to
# min_xz, so (0,0) is the bottom-left page in the grid). Value is an
# Image (or null if no page resident at that coord).
var _images_by_local_coord: Dictionary = {}


## Configure for a ring of the given extent + page size. Worst-case
## pages-per-side derived from how many pages can the ring span when
## offset arbitrarily.
func configure(ring_extent_m: float, page_extent: float) -> void:
	_ring_extent_m = ring_extent_m
	page_extent_m = page_extent
	# Conservative: ring of N pages wide can straddle N+1 pages when
	# offset (e.g. a 1-page ring straddling a page boundary needs 2).
	# For ring_extent ≤ 1 page → 2; otherwise ceil(extent/page) + 1.
	if page_extent <= 0.0:
		pages_per_side = 1
		return
	var raw: float = ring_extent_m / page_extent
	if raw <= 1.0:
		pages_per_side = 2
	else:
		pages_per_side = int(ceil(raw)) + 1


## Set the world-space min XZ corner of the page grid. Pages added
## via add_page() are mapped relative to this corner.
func set_min_corner(world_min_xz: Vector2) -> void:
	min_xz = world_min_xz


func layer_count() -> int:
	return _images_by_local_coord.size()


## Add a page's heightmap image at its world-space page coord.
## Returns the array layer index (page_y * pages_per_side + page_x)
## relative to min_xz. Idempotent on (page_xz, img) — re-adding the
## same coord replaces the image in-place.
##
## If the page is OUTSIDE the current min_xz grid window (the ring
## moved), this is a no-op + returns -1. Caller should re-set
## min_xz first via set_min_corner().
func add_page(page_xz: Vector2, img: Image) -> int:
	var local: Vector2i = _local_coord(page_xz)
	if local.x < 0 or local.y < 0:
		return -1
	if local.x >= pages_per_side or local.y >= pages_per_side:
		return -1
	var key: String = "%d:%d" % [local.x, local.y]
	_images_by_local_coord[key] = img
	return local.y * pages_per_side + local.x


## Remove a page. Frees its grid slot.
func remove_page(page_xz: Vector2) -> void:
	var local: Vector2i = _local_coord(page_xz)
	if local.x < 0 or local.y < 0:
		return
	if local.x >= pages_per_side or local.y >= pages_per_side:
		return
	var key: String = "%d:%d" % [local.x, local.y]
	_images_by_local_coord.erase(key)


## Returns the array layer index for a page coord, or -1 if not resident.
## Layer index = page_y * pages_per_side + page_x relative to min_xz.
func layer_for_page_coord(page_xz: Vector2) -> int:
	var local: Vector2i = _local_coord(page_xz)
	if local.x < 0 or local.y < 0:
		return -1
	if local.x >= pages_per_side or local.y >= pages_per_side:
		return -1
	var key: String = "%d:%d" % [local.x, local.y]
	if not _images_by_local_coord.has(key):
		return -1
	return local.y * pages_per_side + local.x


## Build the Texture2DArray for the current set of resident pages.
## Returns null if zero pages resident.
##
## Output is a Texture2DArray with `pages_per_side * pages_per_side`
## layers, indexed as `layer = page_y * pages_per_side + page_x`.
## Missing pages (not yet streamed) get a placeholder zero image so
## the array indexing is always valid; the shader treats missing
## pages as flat ground (height = 0.5 → world y = 0).
func build_texture_array() -> Texture2DArray:
	if _images_by_local_coord.is_empty():
		return null
	var total: int = pages_per_side * pages_per_side
	# Pick a representative image to determine page resolution (the
	# placeholder needs the same dimensions for create_from_images to
	# accept them all).
	var any_img: Image = _images_by_local_coord.values()[0]
	var page_n: int = any_img.get_width()
	var imgs: Array = []
	imgs.resize(total)
	for py in range(pages_per_side):
		for px in range(pages_per_side):
			var key: String = "%d:%d" % [px, py]
			var layer: int = py * pages_per_side + px
			if _images_by_local_coord.has(key):
				imgs[layer] = _images_by_local_coord[key]
			else:
				imgs[layer] = _placeholder_image(page_n)
	var arr: Texture2DArray = Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


# --- internal ---

func _local_coord(page_xz: Vector2) -> Vector2i:
	# Convert world page coord → grid-local (0..pages_per_side-1).
	# Page coord here is the world-space origin of the page (multiple
	# of page_extent_m).
	if page_extent_m <= 0.0:
		return Vector2i(-1, -1)
	var lx: int = int(round((page_xz.x - min_xz.x) / page_extent_m))
	var ly: int = int(round((page_xz.y - min_xz.y) / page_extent_m))
	return Vector2i(lx, ly)


func _placeholder_image(n: int) -> Image:
	# Flat 0.5 (= world y = 0 per shader's (h - 0.5) * 2 * scale)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * n * 4)
	for i in range(n * n):
		bytes.encode_float(i * 4, 0.5)
	return Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
