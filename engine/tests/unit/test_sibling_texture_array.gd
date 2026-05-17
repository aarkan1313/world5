## Tests for SiblingTextureArray — assembles the runtime Texture2DArray
## from a MaterialVariants manifest + on-disk PBR images.
##
## Per spec 24 Layer 1 + spec 25. The shader binder (Phase 5.5)
## consumes a Texture2DArray; this is the loader that builds it.

extends GutTest


const FIXTURE_DIR := "user://_sibling_tex_fixture"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_DIR))


func _write_image(rel_path: String, color: Color, size: int = 16) -> String:
	# Writes a solid-color PNG to user://_sibling_tex_fixture/<rel_path>.
	# Returns the user:// path so tests can construct manifests against it.
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var full: String = "%s/%s" % [FIXTURE_DIR, rel_path]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(full.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path(full))
	return full


func _build_variants(slot_specs: Array) -> MaterialVariants:
	# slot_specs: Array of {biome, slot, variants: Array of {id, source, weight}}
	var d: Dictionary = {
		"world_seed": 42,
		"region_size_m": 512.0,
		"edge_blend_m": 48.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": slot_specs,
	}
	var path: String = "%s/_manifest.json" % FIXTURE_DIR
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	return MaterialVariants.from_file(path)


# --- empty/missing handling ---

func test_empty_manifest_returns_empty_array() -> void:
	# No variants → an empty Texture2DArray + an empty slot window table.
	# Legitimate state for fresh walking demo before Phase 5.4 promotion.
	var mv: MaterialVariants = _build_variants([])
	var sta: SiblingTextureArray = SiblingTextureArray.build(mv, FIXTURE_DIR, "albedo")
	assert_not_null(sta)
	assert_eq(sta.layer_count(), 0)
	assert_eq(sta.slot_windows.size(), 0)


func test_missing_files_skipped_with_warning() -> void:
	# Manifest names variants whose images don't exist on disk. Loader
	# logs + skips (doesn't crash). Result has 0 layers.
	# Source is biome-relative per spec 24 — resolved as
	# materials/biome_<biome>/<source>/<map>.png
	var mv: MaterialVariants = _build_variants([
		{"biome": "alpine", "slot": "ground", "variants": [
			{"id": "ghost", "source": "ground_variants/ghost", "weight": 1.0},
		]},
	])
	var sta: SiblingTextureArray = SiblingTextureArray.build(mv, FIXTURE_DIR, "albedo")
	assert_not_null(sta)
	assert_eq(sta.layer_count(), 0)


# --- happy path ---

func test_three_variants_one_slot() -> void:
	# Source field is biome-relative; resolution adds biome_<biome>/
	_write_image("biome_test/ground/albedo.png", Color(1.0, 0.0, 0.0, 1.0))
	_write_image("biome_test/ground_variants/v0/albedo.png", Color(0.0, 1.0, 0.0, 1.0))
	_write_image("biome_test/ground_variants/v1/albedo.png", Color(0.0, 0.0, 1.0, 1.0))
	var mv: MaterialVariants = _build_variants([
		{"biome": "test", "slot": "ground", "variants": [
			{"id": "default", "source": "ground", "weight": 1.0},
			{"id": "v0", "source": "ground_variants/v0", "weight": 1.0},
			{"id": "v1", "source": "ground_variants/v1", "weight": 1.0},
		]},
	])
	var sta: SiblingTextureArray = SiblingTextureArray.build(mv, FIXTURE_DIR, "albedo")
	assert_not_null(sta)
	assert_eq(sta.layer_count(), 3)
	assert_eq(sta.slot_windows.size(), 1)
	var window: Dictionary = sta.window_for("test", "ground")
	assert_eq(int(window["start"]), 0)
	assert_eq(int(window["count"]), 3)
	# The returned Texture2DArray must be a real Texture2DArray
	assert_true(sta.texture is Texture2DArray)


func test_multiple_slots_concatenated() -> void:
	_write_image("biome_a/g/albedo.png", Color(1, 0, 0, 1))
	_write_image("biome_a/g_v/v0/albedo.png", Color(0.9, 0, 0, 1))
	_write_image("biome_a/r/albedo.png", Color(0, 1, 0, 1))
	var mv: MaterialVariants = _build_variants([
		{"biome": "a", "slot": "ground", "variants": [
			{"id": "default", "source": "g", "weight": 1.0},
			{"id": "v0", "source": "g_v/v0", "weight": 1.0},
		]},
		{"biome": "a", "slot": "rock", "variants": [
			{"id": "default", "source": "r", "weight": 1.0},
		]},
	])
	var sta: SiblingTextureArray = SiblingTextureArray.build(mv, FIXTURE_DIR, "albedo")
	assert_eq(sta.layer_count(), 3)
	var ground: Dictionary = sta.window_for("a", "ground")
	var rock: Dictionary = sta.window_for("a", "rock")
	assert_eq(int(ground["start"]), 0)
	assert_eq(int(ground["count"]), 2)
	assert_eq(int(rock["start"]), 2)
	assert_eq(int(rock["count"]), 1)


func test_window_for_unknown_returns_zero() -> void:
	var mv: MaterialVariants = _build_variants([])
	var sta: SiblingTextureArray = SiblingTextureArray.build(mv, FIXTURE_DIR, "albedo")
	var window: Dictionary = sta.window_for("missing", "slot")
	assert_eq(int(window["count"]), 0,
		"unknown (biome, slot) returns count=0 (safe default for shader)")


# --- size enforcement ---

func test_mismatched_sizes_skip_offender() -> void:
	# Sibling textures must be authored at consistent size per spec 25.
	# Loader is lenient at runtime: log + skip the offender, keep the
	# rest. Better than refusing to render the whole world.
	_write_image("biome_x/g/albedo.png", Color(1, 0, 0, 1), 16)
	_write_image("biome_x/g_v/v0/albedo.png", Color(0, 1, 0, 1), 32)  # wrong size
	var mv: MaterialVariants = _build_variants([
		{"biome": "x", "slot": "ground", "variants": [
			{"id": "default", "source": "g", "weight": 1.0},
			{"id": "v0", "source": "g_v/v0", "weight": 1.0},
		]},
	])
	var sta: SiblingTextureArray = SiblingTextureArray.build(mv, FIXTURE_DIR, "albedo")
	assert_eq(sta.layer_count(), 1,
		"size-mismatched variant must be skipped; first variant survives")
	var window: Dictionary = sta.window_for("x", "ground")
	assert_eq(int(window["count"]), 1)
