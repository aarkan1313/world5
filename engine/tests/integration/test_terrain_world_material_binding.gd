## Integration test: TerrainWorld wires SiblingTextureArray +
## DetailTextureArray into the per-ring shader materials at world load.
##
## Phase 5.5 extension. The loaders + binders existed before this test;
## this proves _load_world_bundle() actually calls them. Without the
## wire-up the new loaders are dead code.

extends GutTest


const FIXTURE_ROOT := "user://_tw_material_fixture"


var _budget: StreamingBudget
var _scheduler: JobScheduler
var _tracker: GpuResourceTracker
var _tw: TerrainWorld
var _camera: Node3D


func before_each() -> void:
	_budget = StreamingBudget.new()
	_budget.name = "StreamingBudget"
	get_tree().root.add_child(_budget)
	_scheduler = JobScheduler.new()
	_scheduler.name = "JobScheduler"
	get_tree().root.add_child(_scheduler)
	_tracker = GpuResourceTracker.new()
	_tracker.name = "GpuResourceTracker"
	get_tree().root.add_child(_tracker)
	_camera = Node3D.new()
	_camera.name = "Camera"
	get_tree().root.add_child(_camera)
	_tw = TerrainWorld.new()
	_tw.name = "TerrainWorld"
	_tw.ring_count = 2  # smallest possible — fast init
	_tw.ring_vertex_grid = 16
	_tw.inner_cell_size_m = 1.0
	_tw.page_extent_m = 16.0
	_tw.terrain_pages_max = 8
	_tw.camera_path = NodePath("../Camera")


func after_each() -> void:
	if _tw != null and is_instance_valid(_tw):
		_tw.free()
	if _camera != null and is_instance_valid(_camera):
		_camera.free()
	if _scheduler != null and is_instance_valid(_scheduler):
		_scheduler.free()
	if _budget != null and is_instance_valid(_budget):
		_budget.free()
	if _tracker != null and is_instance_valid(_tracker):
		_tracker.free()


func _write_image(rel_path: String, color: Color, size: int = 8) -> void:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var full: String = "%s/%s" % [FIXTURE_ROOT, rel_path]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(full.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path(full))


func _write_json(rel_path: String, content: Dictionary) -> void:
	var full: String = "%s/%s" % [FIXTURE_ROOT, rel_path]
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(full.get_base_dir()))
	var f: FileAccess = FileAccess.open(full, FileAccess.WRITE)
	f.store_string(JSON.stringify(content, "  "))
	f.close()


func _build_world_with_textures() -> String:
	# Clean fixture dir
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_ROOT))
	# A 1-biome bundle with one base + 2 siblings + 2 detail tiles.
	# Source paths are biome-relative per spec 24 short form.
	_write_image("materials/biome_alpine/ground/albedo.png", Color(1, 0, 0, 1))
	_write_image("materials/biome_alpine/ground_variants/v0_a/albedo.png",
		Color(0, 1, 0, 1))
	_write_image("materials/biome_alpine/ground_variants/v1_b/albedo.png",
		Color(0, 0, 1, 1))
	_write_image("materials/biome_alpine/detail/wet_albedo.png",
		Color(0.2, 0.2, 0.8, 0.7))
	_write_image("materials/biome_alpine/detail/moss_albedo.png",
		Color(0.1, 0.6, 0.2, 0.5))
	_write_json("material_variants.json", {
		"_schema_version": 1,
		"world_seed": 42,
		"region_size_m": 512.0,
		"edge_blend_m": 48.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [{
			"biome": "alpine",
			"slot": "ground",
			"variants": [
				{"id": "default", "source": "ground", "weight": 1.0},
				{"id": "v0_a", "source": "ground_variants/v0_a", "weight": 1.0},
				{"id": "v1_b", "source": "ground_variants/v1_b", "weight": 1.0},
			],
		}],
	})
	_write_json("materials/biome_alpine/detail_array.json", {
		"_schema_version": 1,
		"biome": "alpine",
		"detail_tiles": ["wet", "moss"],
		"slot_blends": {
			"ground": {"wet": 0.6, "moss": 0.4},
		},
	})
	# Trailing slash matches the convention _load_world_bundle uses
	# when concatenating ("bundle_path + 'macro_albedo.json'")
	return FIXTURE_ROOT + "/"


func _build_world_no_textures() -> String:
	# Manifests with empty variants — proves unbound path still works
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_ROOT))
	_write_json("material_variants.json", {
		"_schema_version": 1,
		"world_seed": 42,
		"region_size_m": 512.0,
		"edge_blend_m": 48.0,
		"max_variants_per_slot": 8,
		"max_total_variant_layers": 256,
		"slots": [],
	})
	return FIXTURE_ROOT + "/"


# --- happy path: bundle with textures → has_siblings true on rings ---

func test_world_with_textures_flips_has_siblings_on_all_rings() -> void:
	_tw.world_bundle_path = _build_world_with_textures()
	get_tree().root.add_child(_tw)
	# Confirm the wire-up: every ring's material has has_siblings=true
	var ring_count: int = 0
	for c in _tw.get_children():
		if c is MeshInstance3D and c.name.begins_with("ClipmapRing_L"):
			ring_count += 1
			var mat: ShaderMaterial = c.material_override as ShaderMaterial
			assert_not_null(mat,
				"ring %s has ShaderMaterial override" % c.name)
			assert_eq((mat.get_shader_parameter("has_siblings") as bool), true,
				"ring %s has_siblings must be true after world load" % c.name)
			assert_eq(int(mat.get_shader_parameter("sibling_count")), 3,
				"ring %s sibling_count must reflect manifest (3 variants)" % c.name)
	assert_gt(ring_count, 0, "test must find at least one ring")


func test_world_with_textures_flips_has_detail_on_all_rings() -> void:
	_tw.world_bundle_path = _build_world_with_textures()
	get_tree().root.add_child(_tw)
	for c in _tw.get_children():
		if c is MeshInstance3D and c.name.begins_with("ClipmapRing_L"):
			var mat: ShaderMaterial = c.material_override as ShaderMaterial
			assert_eq((mat.get_shader_parameter("has_detail") as bool), true,
				"ring %s has_detail must be true after world load" % c.name)
			assert_eq(int(mat.get_shader_parameter("detail_count")), 2,
				"ring %s detail_count must reflect manifest (2 tiles)" % c.name)


# --- unbound path: empty manifest → has_siblings stays false ---

func test_empty_manifest_leaves_has_siblings_false() -> void:
	_tw.world_bundle_path = _build_world_no_textures()
	get_tree().root.add_child(_tw)
	for c in _tw.get_children():
		if c is MeshInstance3D and c.name.begins_with("ClipmapRing_L"):
			var mat: ShaderMaterial = c.material_override as ShaderMaterial
			assert_eq((mat.get_shader_parameter("has_siblings") as bool), false,
				"empty manifest must keep has_siblings false (legacy path)")


func test_missing_manifest_does_not_crash() -> void:
	# Bundle exists but no material_variants.json — must not crash;
	# the binders stay unbound, render falls through to macro-only.
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_ROOT))
	# Don't write anything else
	_tw.world_bundle_path = FIXTURE_ROOT + "/"
	get_tree().root.add_child(_tw)
	# Just being able to add_child without crashing is the bar; no
	# bundle file existed.
	assert_not_null(_tw)
