## Emits GPU-computed terrain heights to disk so pytest can diff
## them against the Python NoiseStackKernel reference.
##
## Per the SA2-C2.1 cross-impl parity pattern: gut produces canonical
## JSON; Python re-runs equivalent math; pytest diffs bit-for-bit
## (or within 1e-3 tolerance for float kernels).
##
## Only the emitter is here; the actual diff happens in
## tests/integration/test_terrain_backend_parity.py.

extends GutTest


const OUT_DIR := "user://_terrain_parity_emit"


# Test cases mirror what the Python parity test will request. Cover
# positive + negative coords + extreme seeds to catch sign-handling
# parity drift (TB-REV-S1).
const _CASES := [
	{
		"name": "origin_seed42",
		"world_xz": [0.0, 0.0],
		"extent_m": 256.0,
		"grid_n": 16,
		"seed": 42,
	},
	{
		"name": "offset_seed7",
		"world_xz": [1024.0, 512.0],
		"extent_m": 256.0,
		"grid_n": 32,
		"seed": 7,
	},
	{
		"name": "negative_origin",
		"world_xz": [-512.0, -512.0],
		"extent_m": 256.0,
		"grid_n": 16,
		"seed": 13,
	},
	{
		"name": "fractional_negative",
		"world_xz": [-1.5, -3.7],
		"extent_m": 64.0,
		"grid_n": 16,
		"seed": 1,
	},
	{
		"name": "seed_zero",
		"world_xz": [0.0, 0.0],
		"extent_m": 256.0,
		"grid_n": 8,
		"seed": 0,
	},
	{
		"name": "seed_max",
		"world_xz": [0.0, 0.0],
		"extent_m": 256.0,
		"grid_n": 8,
		"seed": 0xFFFFFFFF,
	},
]


var _backend: GpuTerrainBackend = null


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_backend = GpuTerrainBackend.new()


func after_all() -> void:
	if _backend != null:
		_backend.shutdown()
		_backend = null


func test_emit_all_cases() -> void:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null:
		pending("RenderingDevice unavailable (--headless); parity emit skipped")
		return

	var backend: GpuTerrainBackend = _backend
	for case in _CASES:
		var req: TerrainPageRequest = TerrainPageRequest.from_dict({
			"world_xz": Vector2(case["world_xz"][0], case["world_xz"][1]),
			"extent_m": case["extent_m"],
			"grid_n": case["grid_n"],
			"seed": case["seed"],
			"tier": "high",
			"capabilities": ["height_cpu"],
		})
		var res: TerrainPageResult = backend.generate_page(req)
		assert_true(res.has_capability("height_cpu"),
			"case %s emitted heights" % case["name"])

		# Write JSON: { params, heights: [...] }
		var payload := {
			"name": case["name"],
			"world_xz": case["world_xz"],
			"extent_m": case["extent_m"],
			"grid_n": case["grid_n"],
			"seed": case["seed"],
			# fBm hard-coded params from GpuTerrainBackend Phase 4.2:
			"octaves": 6,
			"frequency": 1.0 / 512.0,
			"lacunarity": 2.0,
			"gain": 0.5,
			"amplitude": 50.0,
			"heights": Array(res.height_cpu),
		}
		var path: String = "%s/%s.json" % [OUT_DIR, case["name"]]
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		assert_not_null(f, "open %s for write" % path)
		f.store_string(JSON.stringify(payload))
		f.close()
