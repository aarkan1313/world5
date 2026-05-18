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
## In-memory mip pyramid (Sprint 4a). Mode name → Array of
## Dict{grid: PackedFloat32Array, rows: int, cols: int}, ordered
## fine→coarse. mip 0 = full resolution = same as features[mode].
## Built at load time by _build_mip_pyramids. Sample helpers pick the
## right mip given a `cell_size_m_hint` (e.g. ring cell size). This
## eliminates ring-stitching cracks: adjacent rings sampling at
## matching mips get matching DEM values where their cell-grids meet.
var mip_pyramids: Dictionary = {}
## Same shape for the base height grid (mode "_heights").
const _HEIGHTS_KEY := "_heights"


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

	# Build mip pyramids for the base heights + every feature.
	# Each pyramid level is the prior level downsampled 2:1 via box
	# average (cheap, mathematically correct for elevation averages).
	src._build_mip_pyramids()

	Log.info("dem_source", "loaded", {
		"id": src.id,
		"rows": src.rows,
		"cols": src.cols,
		"bounds": src.bounds_world_xz,
		"elev": src.elevation_range_m,
		"features": src.features.keys(),
		"mip_levels": src.mip_levels_for(_HEIGHTS_KEY),
		"content_hash": src.content_hash.substr(0, 12),
	})
	return src


## Build in-memory mip pyramid for the base heights + each feature.
## Each level is 2:1 box-averaged. Stops when grid drops below 4×4
## (further downsampling discards too much information). Called once
## at load time.
func _build_mip_pyramids() -> void:
	mip_pyramids.clear()
	mip_pyramids[_HEIGHTS_KEY] = _build_pyramid(heights, rows, cols)
	for mode in features.keys():
		mip_pyramids[String(mode)] = _build_pyramid(
			features[mode], rows, cols)


static func _build_pyramid(grid: PackedFloat32Array,
		src_rows: int, src_cols: int) -> Array:
	var pyramid: Array = []
	# Mip 0 = full resolution (alias to source grid; sample helpers
	# treat this as the base case).
	pyramid.append({
		"grid": grid,
		"rows": src_rows,
		"cols": src_cols,
	})
	var cur: PackedFloat32Array = grid
	var cur_rows: int = src_rows
	var cur_cols: int = src_cols
	while cur_rows >= 8 and cur_cols >= 8:
		# 2:1 downsample via 2×2 box average.
		var nr: int = cur_rows >> 1  # integer division by 2
		var nc: int = cur_cols >> 1
		var next: PackedFloat32Array = PackedFloat32Array()
		next.resize(nr * nc)
		for y in range(nr):
			var y0: int = y * 2
			var y1: int = y0 + 1
			for x in range(nc):
				var x0: int = x * 2
				var x1: int = x0 + 1
				var sum: float = (
					cur[y0 * cur_cols + x0] + cur[y0 * cur_cols + x1] +
					cur[y1 * cur_cols + x0] + cur[y1 * cur_cols + x1])
				next[y * nc + x] = sum * 0.25
		pyramid.append({
			"grid": next,
			"rows": nr,
			"cols": nc,
		})
		cur = next
		cur_rows = nr
		cur_cols = nc
	return pyramid


## Number of mip levels for a given mode (or _HEIGHTS_KEY). Returns 0
## if the mode isn't loaded.
func mip_levels_for(mode: String) -> int:
	if not mip_pyramids.has(mode):
		return 0
	return (mip_pyramids[mode] as Array).size()


## Bilinear-sample the DEM at world-XZ coordinates. Out-of-bounds
## returns the clamped-edge value (matches scipy.ndimage mode="reflect"
## within a single edge layer; sufficient for v1's small-patch worlds).
##
## cell_size_m_hint: caller's preferred world-meters per sample (e.g.
## the ring's cell size). Sprint 4a picks the matching mip from the
## pyramid so adjacent rings sampling at matching mips get matching
## DEM values where their cell-grids meet (eliminates ring-stitching
## cracks). Pass 0 for the full-resolution path.
func sample_world_xz(world_x: float, world_z: float,
		cell_size_m_hint: float = 0.0) -> float:
	var mip: Dictionary = _pick_mip(_HEIGHTS_KEY, cell_size_m_hint)
	if mip.is_empty():
		return _bilinear_sample_grid(heights, rows, cols, world_x, world_z)
	return _bilinear_sample_grid(mip["grid"], int(mip["rows"]),
		int(mip["cols"]), world_x, world_z)


## Bilinear-sample a pre-baked feature at world-XZ. Returns 0.0 if the
## requested mode isn't loaded. Feature values are already in feature
## units (rescaled from PNG 0..1 by DemSource.from_bundle).
##
## cell_size_m_hint as above.
func sample_feature_world_xz(mode: String, world_x: float, world_z: float,
		cell_size_m_hint: float = 0.0) -> float:
	if not features.has(mode):
		return 0.0
	var mip: Dictionary = _pick_mip(mode, cell_size_m_hint)
	if mip.is_empty():
		return _bilinear_sample_grid(features[mode], rows, cols, world_x, world_z)
	return _bilinear_sample_grid(mip["grid"], int(mip["rows"]),
		int(mip["cols"]), world_x, world_z)


## Returns true if a pre-baked feature for `mode` is loaded.
func has_feature(mode: String) -> bool:
	return features.has(mode)


# --- mip selection ---

# Pick the mip level matching the caller's requested cell size.
# Returns an empty Dict to fall back to the base grid.
#
# Strategy: walk pyramid from fine (mip 0) to coarse, picking the
# COARSEST mip whose cell size is still <= hint. This way:
# - Near rings (small hint) sample fine mips (lots of detail).
# - Far rings (large hint) sample coarse mips (matching their grid).
# - Adjacent rings sampling at hint=A and hint=2A pick mips one step
#   apart, so DEM values at shared cells match exactly — fixes ring-
#   stitching cracks.
func _pick_mip(mode: String, cell_size_m_hint: float) -> Dictionary:
	if cell_size_m_hint <= 0.0:
		return {}
	if not mip_pyramids.has(mode):
		return {}
	var pyramid: Array = mip_pyramids[mode]
	if pyramid.is_empty():
		return {}
	var world_w: float = bounds_world_xz.size.x
	var best: Dictionary = pyramid[0]
	for i in range(pyramid.size()):
		var mip: Dictionary = pyramid[i]
		var mip_cell: float = world_w / max(float(int(mip["cols"]) - 1), 1.0)
		if mip_cell <= cell_size_m_hint:
			best = mip
		else:
			break
	return best


# Shared bilinear sample helper. The grid is row-major (y * cols + x);
# world-XZ → (col, row) via bounds_world_xz.
func _bilinear_sample_grid(grid: PackedFloat32Array,
		grid_rows: int, grid_cols: int,
		world_x: float, world_z: float) -> float:
	if grid_rows <= 0 or grid_cols <= 0 or grid.size() < grid_rows * grid_cols:
		return 0.0
	var u: float = (world_x - bounds_world_xz.position.x) / bounds_world_xz.size.x
	var v: float = (world_z - bounds_world_xz.position.y) / bounds_world_xz.size.y
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)
	var fx: float = u * float(grid_cols - 1)
	var fy: float = v * float(grid_rows - 1)
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var x1: int = min(x0 + 1, grid_cols - 1)
	var y1: int = min(y0 + 1, grid_rows - 1)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var v00: float = grid[y0 * grid_cols + x0]
	var v10: float = grid[y0 * grid_cols + x1]
	var v01: float = grid[y1 * grid_cols + x0]
	var v11: float = grid[y1 * grid_cols + x1]
	var vx0: float = lerp(v00, v10, tx)
	var vx1: float = lerp(v01, v11, tx)
	return lerp(vx0, vx1, ty)
