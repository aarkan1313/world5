## DemSource — bundle-side DEM loader (sidecar + height grid).
##
## Per spec 19 §"DEM source handling defined upfront" + Sprint 3 of
## the DEM/runtime-kernels epic.
##
## Reads `<bundle>/dem/<id>.json` (matching dem_source.schema.json) +
## the companion `<bundle>/dem/<id>.png` (16-bit single-channel
## elevation, normalized to [0, 1] by the sidecar's elevation_range_m).
## Emits a PackedFloat32Array of world-meter heights + metadata for
## DemFeatureKernel sampling.
##
## v1 (Sprint 3): RAM-load the entire DEM. Fine for walking_demo's
## ~4 km Cascades patch (~16 MB). Sprint 4 adds tile streaming for
## procedural-infinite worlds; this class stays the same shape, just
## with on-demand tile fetch instead of full RAM load.
##
## We use PNG instead of GeoTIFF because Godot ships GIF/JPG/PNG/WebP
## decoders but not GDAL — using PNG keeps the runtime dependency-
## free. The pipeline tool tx_dem_prepare emits BOTH the GeoTIFF (for
## the Python reference) AND the PNG (for the runtime). Both round-
## trip the same data at 16-bit precision (~1.5cm at 1km range).

class_name DemSource extends RefCounted


## Bundle-local source ID (mirrors sidecar `id`).
var id: String = ""
## World-XZ bounds [min_x, min_z, max_x, max_z] in meters.
var bounds_world_xz: Rect2 = Rect2()
## Elevation range [min_m, max_m] in meters above sea level.
var elevation_range_m: Vector2 = Vector2()
## CRS string from the sidecar (informational; runtime only cares
## about world-XZ, not CRS).
var crs: String = ""
## Source resolution in meters per cell (informational).
var source_resolution_m: float = 0.0
## Attribution string for downstream UI display.
var attribution: String = ""
## The decoded elevation grid in WORLD METERS (float). Row-major;
## (0, 0) = (bounds_world_xz.position) = min_x, min_z corner.
var heights: PackedFloat32Array = PackedFloat32Array()
## Grid dimensions (rows, cols).
var rows: int = 0
var cols: int = 0
## Hash of the source PNG file contents — participates in cache keys
## so DEM swaps invalidate downstream bakes per spec 12.
var content_hash: String = ""
## Pre-baked DEM feature grids (Sprint 3 bake-route). Mode name →
## PackedFloat32Array in feature units (already rescaled from PNG
## [0, 1] to the per-feature range from the sidecar). Empty if the
## sidecar didn't declare any features.
var features: Dictionary = {}
## Per-feature [min, max] ranges (informational; the heights above
## are already in feature units, not normalized).
var feature_ranges: Dictionary = {}


## Load a DemSource from a bundle by ID. Returns null + logs on
## failure. Resolves:
##   <bundle_path>/dem/<id>.json   (sidecar; required)
##   <bundle_path>/dem/<id>.png    (height grid; required)
static func from_bundle(bundle_path: String, source_id: String) -> DemSource:
	# Normalize bundle_path to end with /
	var root: String = bundle_path
	if not root.ends_with("/"):
		root += "/"
	var sidecar_path: String = "%sdem/%s.json" % [root, source_id]
	var png_path: String = "%sdem/%s.png" % [root, source_id]

	var sf: FileAccess = FileAccess.open(sidecar_path, FileAccess.READ)
	if sf == null:
		Log.error("dem_source", "sidecar not found",
			{"id": source_id, "path": sidecar_path})
		return null
	var sidecar_text: String = sf.get_as_text()
	sf.close()
	var parsed: Variant = JSON.parse_string(sidecar_text)
	if not (parsed is Dictionary):
		Log.error("dem_source", "sidecar parse failed",
			{"id": source_id, "path": sidecar_path})
		return null
	var sidecar: Dictionary = parsed

	var src := DemSource.new()
	src.id = String(sidecar.get("id", source_id))
	src.crs = String(sidecar.get("crs", ""))
	src.source_resolution_m = float(sidecar.get("source_resolution_m", 0.0))
	src.attribution = String(sidecar.get("attribution", ""))

	# bounds_world_xz: [min_x, min_z, max_x, max_z]
	var b: Array = sidecar.get("bounds_world_xz", []) as Array
	if b.size() != 4:
		Log.error("dem_source", "bounds_world_xz wrong length",
			{"id": source_id, "got": b.size()})
		return null
	src.bounds_world_xz = Rect2(
		Vector2(float(b[0]), float(b[1])),
		Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1])),
	)
	if src.bounds_world_xz.size.x <= 0.0 or src.bounds_world_xz.size.y <= 0.0:
		Log.error("dem_source", "bounds_world_xz has non-positive extent",
			{"id": source_id, "size": src.bounds_world_xz.size})
		return null

	var er: Array = sidecar.get("elevation_range_m", []) as Array
	if er.size() != 2:
		Log.error("dem_source", "elevation_range_m wrong length",
			{"id": source_id, "got": er.size()})
		return null
	src.elevation_range_m = Vector2(float(er[0]), float(er[1]))
	if src.elevation_range_m.y <= src.elevation_range_m.x:
		Log.error("dem_source", "elevation_range_m max <= min",
			{"id": source_id, "range": src.elevation_range_m})
		return null

	# Load PNG (16-bit single-channel = Image.FORMAT_RH after import,
	# or FORMAT_R8 for 8-bit fallback). We decode whatever Image gives
	# us and convert to float32 in world meters.
	if not FileAccess.file_exists(png_path):
		Log.error("dem_source", "height PNG not found",
			{"id": source_id, "path": png_path})
		return null
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(png_path))
	if img == null:
		Log.error("dem_source", "height PNG load failed",
			{"id": source_id, "path": png_path})
		return null
	src.cols = img.get_width()
	src.rows = img.get_height()
	if src.cols <= 0 or src.rows <= 0:
		Log.error("dem_source", "height PNG has zero extent",
			{"id": source_id, "cols": src.cols, "rows": src.rows})
		return null

	# Decode: read each pixel's R channel (0..1 normalized) and rescale
	# to elevation_range_m. Image.get_pixel returns Color with r in [0,1]
	# regardless of underlying format.
	src.heights.resize(src.rows * src.cols)
	var elev_min: float = src.elevation_range_m.x
	var elev_span: float = src.elevation_range_m.y - src.elevation_range_m.x
	for y in range(src.rows):
		for x in range(src.cols):
			var t: float = img.get_pixel(x, y).r
			src.heights[y * src.cols + x] = elev_min + t * elev_span

	# Content hash for cache participation: SHA256 of raw PNG bytes.
	var f: FileAccess = FileAccess.open(png_path, FileAccess.READ)
	if f != null:
		var data: PackedByteArray = f.get_buffer(f.get_length())
		f.close()
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(data)
		src.content_hash = ctx.finish().hex_encode()

	# Pre-baked features (Sprint 3 bake-route). Sidecar has
	# `features.paths: {mode: png_path}` + `features.ranges:
	# {mode: [min, max]}`. We load each PNG, rescale [0,1] → range.
	var feat_blob: Dictionary = sidecar.get("features", {}) as Dictionary
	if not feat_blob.is_empty():
		var paths: Dictionary = feat_blob.get("paths", {}) as Dictionary
		var ranges: Dictionary = feat_blob.get("ranges", {}) as Dictionary
		for mode in paths.keys():
			var rel: String = String(paths[mode])
			var rng: Array = ranges.get(mode, [0.0, 1.0]) as Array
			if rng.size() != 2:
				continue
			var feat_path: String = root + rel
			if not FileAccess.file_exists(feat_path):
				Log.warn("dem_source", "feature PNG missing",
					{"id": source_id, "mode": mode, "path": feat_path})
				continue
			var feat_img: Image = Image.load_from_file(
				ProjectSettings.globalize_path(feat_path))
			if feat_img == null:
				Log.warn("dem_source", "feature PNG load failed",
					{"id": source_id, "mode": mode, "path": feat_path})
				continue
			if feat_img.get_width() != src.cols or feat_img.get_height() != src.rows:
				Log.warn("dem_source", "feature PNG dim mismatch",
					{"id": source_id, "mode": mode,
					 "want": Vector2i(src.cols, src.rows),
					 "got": feat_img.get_size()})
				continue
			var arr: PackedFloat32Array = PackedFloat32Array()
			arr.resize(src.rows * src.cols)
			var f_min: float = float(rng[0])
			var f_span: float = float(rng[1]) - f_min
			for y in range(src.rows):
				for x in range(src.cols):
					var t2: float = feat_img.get_pixel(x, y).r
					arr[y * src.cols + x] = f_min + t2 * f_span
			src.features[String(mode)] = arr
			src.feature_ranges[String(mode)] = Vector2(f_min, float(rng[1]))

	Log.info("dem_source", "loaded", {
		"id": src.id,
		"rows": src.rows,
		"cols": src.cols,
		"bounds": src.bounds_world_xz,
		"elev": src.elevation_range_m,
		"features": src.features.keys(),
		"content_hash": src.content_hash.substr(0, 12),
	})
	return src


## Bilinear-sample the DEM at world-XZ coordinates. Out-of-bounds
## returns the clamped-edge value (matches scipy.ndimage mode="reflect"
## within a single edge layer; sufficient for v1's small-patch worlds).
func sample_world_xz(world_x: float, world_z: float) -> float:
	return _bilinear_sample_grid(heights, world_x, world_z)


## Bilinear-sample a pre-baked feature at world-XZ. Returns 0.0 if the
## requested mode isn't loaded. Feature values are already in feature
## units (rescaled from PNG 0..1 by DemSource.from_bundle).
func sample_feature_world_xz(mode: String, world_x: float, world_z: float) -> float:
	if not features.has(mode):
		return 0.0
	return _bilinear_sample_grid(features[mode], world_x, world_z)


## Returns true if a pre-baked feature for `mode` is loaded.
func has_feature(mode: String) -> bool:
	return features.has(mode)


# Shared bilinear sample helper. The grid is row-major (y * cols + x);
# world-XZ → (col, row) via bounds_world_xz.
func _bilinear_sample_grid(grid: PackedFloat32Array,
		world_x: float, world_z: float) -> float:
	if rows <= 0 or cols <= 0 or grid.size() < rows * cols:
		return 0.0
	var u: float = (world_x - bounds_world_xz.position.x) / bounds_world_xz.size.x
	var v: float = (world_z - bounds_world_xz.position.y) / bounds_world_xz.size.y
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)
	var fx: float = u * float(cols - 1)
	var fy: float = v * float(rows - 1)
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var x1: int = min(x0 + 1, cols - 1)
	var y1: int = min(y0 + 1, rows - 1)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var v00: float = grid[y0 * cols + x0]
	var v10: float = grid[y0 * cols + x1]
	var v01: float = grid[y1 * cols + x0]
	var v11: float = grid[y1 * cols + x1]
	var vx0: float = lerp(v00, v10, tx)
	var vx1: float = lerp(v01, v11, tx)
	return lerp(vx0, vx1, ty)
