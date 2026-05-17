## Tests for RingHeightArray — per-ring stitched-heightmap state.
##
## Phase 4.9.a (audit C1). The pre-fix renderer bound one heightmap
## page per ring covering only the ring's center; outer rings (extent
## > page_extent_m) stretched the texture at edges, producing visible
## chunk seams. RingHeightArray maintains a Texture2DArray of all
## pages currently resident in the ring + a page_coord → array layer
## table the shader uses to sample the right page per fragment.

extends GutTest


# --- construction + basic geometry ---

func test_constructible() -> void:
	var rha: RingHeightArray = RingHeightArray.new()
	assert_not_null(rha)
	assert_eq(rha.layer_count(), 0)


func test_pages_per_side_for_ring_extent() -> void:
	# A ring that's 510m wide with 256m pages needs at most 3 pages
	# per side (the ring spans up to 3 page columns when offset).
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(510.0, 256.0)
	# Ring extends ±255 around center → covers pages -1, 0, 1 → 3 wide
	assert_eq(rha.pages_per_side, 3)


func test_pages_per_side_inner_ring() -> void:
	# 127.5m ring fits inside one 256m page in best case but can span
	# 2 when offset; the conservative size is 2 per side.
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(127.5, 256.0)
	assert_eq(rha.pages_per_side, 2)


func test_pages_per_side_outer_ring() -> void:
	# 2040m ring with 256m pages → ceil(2040/256)+1 = 9 per side
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(2040.0, 256.0)
	assert_eq(rha.pages_per_side, 9)


# --- page coord → layer ---

func test_add_page_assigns_spatial_layer() -> void:
	# Phase 4.9.a: layer index = page_y * pages_per_side + page_x
	# so the shader can compute layer purely from world XZ + min_xz +
	# page_extent + pages_per_side (no lookup table needed).
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(510.0, 256.0)
	rha.set_min_corner(Vector2(-512.0, -512.0))
	var img: Image = _solid_height_image(8, 0.5)
	# min_xz = (-512, -512); page_extent = 256; pages_per_side = 3.
	# page at (-512, -512) → local (0, 0) → layer 0
	var l_a: int = rha.add_page(Vector2(-512.0, -512.0), img)
	assert_eq(l_a, 0, "min-corner page → layer 0")
	# page at (-256, -512) → local (1, 0) → layer 1
	var l_b: int = rha.add_page(Vector2(-256.0, -512.0), img)
	assert_eq(l_b, 1, "page +1 in X → layer 1")
	# page at (-512, -256) → local (0, 1) → layer 3 (= 1 * 3 + 0)
	var l_c: int = rha.add_page(Vector2(-512.0, -256.0), img)
	assert_eq(l_c, 3, "page +1 in Z → layer pages_per_side (3)")
	# Idempotent
	var l_a2: int = rha.add_page(Vector2(-512.0, -512.0), img)
	assert_eq(l_a2, 0, "re-adding same coord same layer")
	assert_eq(rha.layer_count(), 3)


func test_add_page_out_of_window_returns_neg_one() -> void:
	# Pages outside the current min_xz grid window are rejected (the
	# ring snap should have updated min_xz first).
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(510.0, 256.0)
	rha.set_min_corner(Vector2(0.0, 0.0))
	var img: Image = _solid_height_image(8, 0.5)
	# Page at (1024, 0) is 4 pages out (pages_per_side = 3 → max idx 2)
	assert_eq(rha.add_page(Vector2(1024.0, 0.0), img), -1)
	# Negative offset also rejected
	assert_eq(rha.add_page(Vector2(-512.0, 0.0), img), -1)
	assert_eq(rha.layer_count(), 0)


func test_layer_for_page_coord() -> void:
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(510.0, 256.0)
	rha.set_min_corner(Vector2(0.0, 0.0))
	var img: Image = _solid_height_image(8, 0.5)
	rha.add_page(Vector2(  0.0,   0.0), img)
	rha.add_page(Vector2(256.0,   0.0), img)
	rha.add_page(Vector2(  0.0, 256.0), img)
	assert_eq(rha.layer_for_page_coord(Vector2(  0.0,   0.0)), 0)
	assert_eq(rha.layer_for_page_coord(Vector2(256.0,   0.0)), 1)
	assert_eq(rha.layer_for_page_coord(Vector2(  0.0, 256.0)), 3,
		"pages_per_side=3 → layer for (0, 256) = 1 * 3 + 0 = 3")
	# Not-yet-added page within window → -1
	assert_eq(rha.layer_for_page_coord(Vector2(512.0, 0.0)), -1)
	# Out of window → -1
	assert_eq(rha.layer_for_page_coord(Vector2(1024.0, 0.0)), -1)


func test_remove_page_clears_layer() -> void:
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(510.0, 256.0)
	rha.set_min_corner(Vector2(0.0, 0.0))
	var img: Image = _solid_height_image(8, 0.5)
	rha.add_page(Vector2(0.0, 0.0), img)
	rha.add_page(Vector2(256.0, 0.0), img)
	assert_eq(rha.layer_count(), 2)
	rha.remove_page(Vector2(0.0, 0.0))
	assert_eq(rha.layer_count(), 1)
	assert_eq(rha.layer_for_page_coord(Vector2(0.0, 0.0)), -1,
		"removed page no longer resolves to a layer")


# --- texture array build ---

func test_build_texture_array_pads_to_full_grid() -> void:
	# Even with one page added, the Texture2DArray has pages_per_side²
	# layers (with placeholders for unstreamed pages) so the shader's
	# spatial layer-index math is always valid.
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(127.5, 256.0)   # pages_per_side = 2 → 4 total
	rha.set_min_corner(Vector2(0.0, 0.0))
	var img: Image = _solid_height_image(8, 0.5)
	rha.add_page(Vector2(0.0, 0.0), img)
	var tex: Texture2DArray = rha.build_texture_array()
	assert_not_null(tex)
	assert_eq(tex.get_layers(), 4,
		"array always has pages_per_side² layers (placeholders for missing)")


func test_build_texture_array_empty_returns_null() -> void:
	# No pages added → null (caller leaves the legacy single-page path
	# active; the array wouldn't render anything anyway)
	var rha: RingHeightArray = RingHeightArray.new()
	rha.configure(127.5, 256.0)
	rha.set_min_corner(Vector2(0.0, 0.0))
	var tex: Texture2DArray = rha.build_texture_array()
	assert_null(tex)


# --- helpers ---

func _solid_height_image(n: int, value: float) -> Image:
	# Single-channel float heightmap, fill with `value`
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(n * n * 4)
	for i in range(n * n):
		bytes.encode_float(i * 4, value)
	return Image.create_from_data(n, n, false, Image.FORMAT_RF, bytes)
