## Tests for DetailTextureArray — assembles the runtime Texture2DArray
## for Layer 2 detail overlays from a DetailArray manifest + on-disk
## PBR overlay images.
##
## Path convention per spec 24: materials/biome_<biome>/detail/
## <tile>_<map>.png (e.g. wet_albedo.png, moss_albedo.png).

extends GutTest


const FIXTURE_DIR := "user://_detail_tex_fixture"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_DIR))


func _write_image(rel_path: String, color: Color, size: int = 16) -> String:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var full: String = "%s/%s" % [FIXTURE_DIR, rel_path]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(full.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path(full))
	return full


func _build_detail(biome: String, tiles: Array, slot_blends: Dictionary = {}) -> DetailArray:
	var d: Dictionary = {
		"biome": biome,
		"detail_tiles": tiles,
		"slot_blends": slot_blends,
	}
	var path: String = "%s/_manifest.json" % FIXTURE_DIR
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	return DetailArray.from_file(path)


# --- empty handling ---

func test_no_tiles_returns_empty_array() -> void:
	# Walking demo's current state (no detail tiles authored yet)
	var da: DetailArray = _build_detail("alpine", [])
	var dta: DetailTextureArray = DetailTextureArray.build(da, FIXTURE_DIR, "albedo")
	assert_not_null(dta)
	assert_eq(dta.layer_count(), 0)


func test_missing_files_skipped() -> void:
	var da: DetailArray = _build_detail("alpine", ["ghost"])
	var dta: DetailTextureArray = DetailTextureArray.build(da, FIXTURE_DIR, "albedo")
	assert_not_null(dta)
	assert_eq(dta.layer_count(), 0,
		"missing detail tile must be skipped, not crash")


# --- happy path ---

func test_three_tiles_load_in_manifest_order() -> void:
	_write_image("biome_alpine/detail/wet_albedo.png", Color(0, 0, 1, 0.8))
	_write_image("biome_alpine/detail/moss_albedo.png", Color(0, 1, 0, 0.6))
	_write_image("biome_alpine/detail/grunge_albedo.png", Color(0.3, 0.2, 0.1, 0.9))
	var da: DetailArray = _build_detail("alpine", ["wet", "moss", "grunge"])
	var dta: DetailTextureArray = DetailTextureArray.build(da, FIXTURE_DIR, "albedo")
	assert_not_null(dta)
	assert_eq(dta.layer_count(), 3)
	# Index 0 = first tile in manifest = "wet"
	assert_eq(dta.layer_index_of("wet"), 0)
	assert_eq(dta.layer_index_of("moss"), 1)
	assert_eq(dta.layer_index_of("grunge"), 2)
	assert_eq(dta.layer_index_of("missing"), -1)
	assert_true(dta.texture is Texture2DArray)


func test_skipped_tile_does_not_shift_indices() -> void:
	# When a middle tile fails to load, downstream tiles in the
	# Texture2DArray shift up — but layer_index_of must report the
	# ACTUAL index in the assembled array, not the manifest's nominal
	# index. This keeps DetailArray.weights_for usable: caller passes
	# the tile name (not the manifest position) to look up the real
	# layer.
	_write_image("biome_alpine/detail/a_albedo.png", Color(1, 0, 0, 1))
	# tile "b" intentionally missing
	_write_image("biome_alpine/detail/c_albedo.png", Color(0, 0, 1, 1))
	var da: DetailArray = _build_detail("alpine", ["a", "b", "c"])
	var dta: DetailTextureArray = DetailTextureArray.build(da, FIXTURE_DIR, "albedo")
	assert_eq(dta.layer_count(), 2)
	assert_eq(dta.layer_index_of("a"), 0)
	assert_eq(dta.layer_index_of("b"), -1, "missing tile = -1")
	assert_eq(dta.layer_index_of("c"), 1, "c shifts down to layer 1")


# --- size mismatch ---

func test_size_mismatch_skips_offender() -> void:
	_write_image("biome_alpine/detail/ok_albedo.png", Color(1, 0, 0, 1), 16)
	_write_image("biome_alpine/detail/bad_albedo.png", Color(0, 1, 0, 1), 32)
	var da: DetailArray = _build_detail("alpine", ["ok", "bad"])
	var dta: DetailTextureArray = DetailTextureArray.build(da, FIXTURE_DIR, "albedo")
	assert_eq(dta.layer_count(), 1)
	assert_eq(dta.layer_index_of("ok"), 0)
	assert_eq(dta.layer_index_of("bad"), -1)
