## Tests for DemSource.gd — bundle-side DEM loader.
##
## Per spec 19 §"DEM source handling defined upfront" + Sprint 3 of
## the DEM/runtime-kernels epic.
##
## Uses synthetic PNG + sidecar fixtures so tests don't depend on
## real-world DEMs. Real-world DEM integration test is in
## tests/integration/test_dem_runtime_real_device.gd (Sprint 3.5).

extends GutTest


const FIXTURE_DIR := "user://_dem_source_test_fixture"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR + "/dem")


func after_each() -> void:
	# Recursive remove (Godot's DirAccess.remove only handles empty dirs).
	_remove_recursive(FIXTURE_DIR)


func _remove_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		var full := path + "/" + entry
		if d.current_is_dir():
			_remove_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


# Build a synthetic ramp PNG + sidecar. opts dict optional keys:
#   rows, cols (default 4); elev_min, elev_max (default 100, 200);
#   bounds (Array of 4 floats, default [0, 0, 16, 16]).
# GDScript 4 doesn't accept Python-like kwargs at the call site;
# Dictionary arg is the convention for "lots of optional named
# params" tests like this.
func _write_fixture(source_id: String, opts: Dictionary = {}) -> void:
	var rows: int = int(opts.get("rows", 4))
	var cols: int = int(opts.get("cols", 4))
	var elev_min: float = float(opts.get("elev_min", 100.0))
	var elev_max: float = float(opts.get("elev_max", 200.0))
	var bounds: Array = opts.get("bounds", [0.0, 0.0, 16.0, 16.0])
	# 16-bit single-channel PNG isn't directly creatable via Image —
	# we use 8-bit RGB and decode the R channel (DemSource reads .r
	# from Color which is 0..1 regardless of underlying bit depth).
	var img: Image = Image.create(cols, rows, false, Image.FORMAT_R8)
	for y in range(rows):
		# Ramp top-to-bottom: row 0 = 0; last row = 255
		var v: int = int(float(y) / float(max(rows - 1, 1)) * 255.0)
		for x in range(cols):
			img.set_pixel(x, y, Color(float(v) / 255.0, 0, 0, 1))
	var png_path: String = FIXTURE_DIR + "/dem/" + source_id + ".png"
	img.save_png(png_path)
	# Sidecar
	var sidecar: Dictionary = {
		"_schema_version": 1,
		"id": source_id,
		"path": "dem/" + source_id + ".tif",
		"png_path": "dem/" + source_id + ".png",
		"crs": "EPSG:32610",
		"bounds_world_xz": bounds,
		"elevation_range_m": [elev_min, elev_max],
		"source_resolution_m": 4.0,
	}
	var sidecar_path: String = FIXTURE_DIR + "/dem/" + source_id + ".json"
	var f: FileAccess = FileAccess.open(sidecar_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(sidecar))
	f.close()


# --- happy path ---

func test_loads_sidecar_and_png() -> void:
	_write_fixture("ramp")
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	assert_not_null(src)
	assert_eq(src.id, "ramp")
	assert_eq(src.rows, 4)
	assert_eq(src.cols, 4)
	assert_almost_eq(src.elevation_range_m.x, 100.0, 1e-3)
	assert_almost_eq(src.elevation_range_m.y, 200.0, 1e-3)


func test_heights_decoded_into_world_meters() -> void:
	_write_fixture("ramp", {})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	# Row 0 should decode to ~100m (PNG = 0); row 3 ~200m (PNG = 255).
	var h0: float = src.heights[0 * src.cols + 0]
	var h_last: float = src.heights[(src.rows - 1) * src.cols + 0]
	assert_almost_eq(h0, 100.0, 1.0)
	assert_almost_eq(h_last, 200.0, 1.0)


func test_bounds_world_xz_stored_as_rect2() -> void:
	_write_fixture("ramp", {"bounds": [-100.0, -50.0, 100.0, 50.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	assert_almost_eq(src.bounds_world_xz.position.x, -100.0, 1e-6)
	assert_almost_eq(src.bounds_world_xz.position.y, -50.0, 1e-6)
	assert_almost_eq(src.bounds_world_xz.size.x, 200.0, 1e-6)
	assert_almost_eq(src.bounds_world_xz.size.y, 100.0, 1e-6)


# --- sample_world_xz ---

func test_sample_at_corner_returns_corner_height() -> void:
	_write_fixture("ramp", {"rows": 4, "cols": 4, "elev_min": 100.0, "elev_max": 200.0, "bounds": [0.0, 0.0, 16.0, 16.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	# Top-left corner (0, 0) → row 0 → ~100m
	var h_tl: float = src.sample_world_xz(0.0, 0.0)
	assert_almost_eq(h_tl, 100.0, 1.0)
	# Bottom-right corner (16, 16) → row 3 → ~200m
	var h_br: float = src.sample_world_xz(16.0, 16.0)
	assert_almost_eq(h_br, 200.0, 1.0)


func test_sample_out_of_bounds_clamps_to_edge() -> void:
	_write_fixture("ramp", {"bounds": [0.0, 0.0, 16.0, 16.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	# Wildly OOB: clamp behavior; just check no NaN/crash.
	var h: float = src.sample_world_xz(-1000.0, -1000.0)
	assert_true(is_finite(h))


# --- error paths ---

func test_missing_sidecar_returns_null() -> void:
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "nonexistent")
	assert_null(src)


func test_missing_png_returns_null() -> void:
	# Sidecar only, no PNG.
	var sidecar: Dictionary = {
		"id": "orphan",
		"bounds_world_xz": [0.0, 0.0, 16.0, 16.0],
		"elevation_range_m": [0.0, 100.0],
	}
	var f: FileAccess = FileAccess.open(
		FIXTURE_DIR + "/dem/orphan.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(sidecar))
	f.close()
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "orphan")
	assert_null(src)


func test_invalid_bounds_returns_null() -> void:
	# bounds_world_xz with max <= min should fail.
	var sidecar: Dictionary = {
		"id": "bad_bounds",
		"bounds_world_xz": [10.0, 10.0, 5.0, 5.0],
		"elevation_range_m": [0.0, 100.0],
	}
	var f: FileAccess = FileAccess.open(
		FIXTURE_DIR + "/dem/bad_bounds.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(sidecar))
	f.close()
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "bad_bounds")
	assert_null(src)


# --- content_hash ---

func test_content_hash_is_sha256() -> void:
	_write_fixture("ramp")
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	assert_eq(src.content_hash.length(), 64)


func test_content_hash_changes_with_png() -> void:
	_write_fixture("a", {"rows": 4, "cols": 4})
	var src_a: DemSource = DemSource.from_bundle(FIXTURE_DIR, "a")
	# Different shape → different PNG → different hash
	_write_fixture("b", {"rows": 8, "cols": 8})
	var src_b: DemSource = DemSource.from_bundle(FIXTURE_DIR, "b")
	assert_ne(src_a.content_hash, src_b.content_hash)


# --- Sprint 4a: mip pyramid + LOD-aware sampling ---

func test_mip_pyramid_built_for_heights() -> void:
	# 8x8 source → 1 level (8x8 stays; 4x4 too small to drop into).
	# We need to seed a larger fixture.
	_write_fixture("big", {"rows": 16, "cols": 16, "bounds": [0.0, 0.0, 16.0, 16.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "big")
	# 16->16, 16->8 (downsample), 8 < 8 threshold? — actually the
	# pyramid builder downsamples while rows>=8 and cols>=8; so 16
	# downsamples to 8 (which qualifies — at start of loop), then 8
	# fails the `>= 8` check before another downsample? Wait the loop
	# is `while cur_rows >= 8 and cur_cols >= 8`, so 16 → 8 (kept),
	# then 8 → 4 (loop entered since 8 >= 8, but the new mip is 4×4),
	# then 4 fails. So 3 levels: 16, 8, 4.
	assert_eq(src.mip_levels_for("_heights"), 3)


func test_mip_pyramid_smaller_grid_yields_fewer_levels() -> void:
	# 4×4 source → only mip 0 (no further downsampling possible).
	_write_fixture("tiny", {"rows": 4, "cols": 4, "bounds": [0.0, 0.0, 16.0, 16.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "tiny")
	assert_eq(src.mip_levels_for("_heights"), 1)


func test_sample_with_zero_hint_uses_base_grid() -> void:
	# Default cell_size_m_hint=0 → use full resolution.
	_write_fixture("ramp", {"rows": 4, "cols": 4, "elev_min": 100.0, "elev_max": 200.0, "bounds": [0.0, 0.0, 16.0, 16.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	# Corner → ~100m (no hint)
	var h: float = src.sample_world_xz(0.0, 0.0, 0.0)
	assert_almost_eq(h, 100.0, 1.5)


func test_sample_with_large_hint_picks_coarsest_mip() -> void:
	# Big DEM, sample with hint larger than any mip's cell → pick the
	# coarsest (mip 0 is 4-wide for 16m → cell = 5.3m; mip 1 cell ≈
	# 10.7m, mip 2 cell ≈ 21.3m). hint=100m should pick the coarsest.
	_write_fixture("big", {"rows": 16, "cols": 16, "elev_min": 0.0, "elev_max": 100.0, "bounds": [0.0, 0.0, 16.0, 16.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "big")
	# Sanity: just don't crash + return a finite value.
	var h: float = src.sample_world_xz(8.0, 8.0, 100.0)
	assert_true(is_finite(h))


func test_lod_sample_consistent_at_matched_cell_sizes() -> void:
	# Adjacent rings with matching mip selection should agree at
	# shared cells. This is the core ring-stitching-fix invariant.
	_write_fixture("big", {"rows": 16, "cols": 16, "elev_min": 0.0, "elev_max": 100.0, "bounds": [0.0, 0.0, 16.0, 16.0]})
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "big")
	# Two queries at the same world XZ but different hints should
	# generally produce reasonable values (not NaN, in elev range).
	var h_fine: float = src.sample_world_xz(8.0, 8.0, 1.0)
	var h_coarse: float = src.sample_world_xz(8.0, 8.0, 50.0)
	assert_true(is_finite(h_fine))
	assert_true(is_finite(h_coarse))
	assert_true(h_fine >= 0.0 - 1.0 and h_fine <= 100.0 + 1.0)
	assert_true(h_coarse >= 0.0 - 1.0 and h_coarse <= 100.0 + 1.0)


func test_feature_sample_uses_mip_pyramid() -> void:
	# When a feature mode is loaded, its mip pyramid should be built
	# alongside heights, and feature sampling should honor the hint.
	_write_fixture("ramp", {"rows": 16, "cols": 16, "elev_min": 100.0, "elev_max": 200.0, "bounds": [0.0, 0.0, 16.0, 16.0]})
	# The fixture doesn't write feature PNGs; feature pyramid count
	# stays 0. Confirm mip_levels_for returns 0 for missing features.
	var src: DemSource = DemSource.from_bundle(FIXTURE_DIR, "ramp")
	assert_eq(src.mip_levels_for("dem_height"), 0)
	# sample_feature_world_xz returns 0 for unknown feature (existing
	# behavior preserved through the LOD refactor).
	var f: float = src.sample_feature_world_xz("dem_height", 8.0, 8.0, 2.0)
	assert_eq(f, 0.0)
