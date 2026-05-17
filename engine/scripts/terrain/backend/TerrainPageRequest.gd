## TerrainPageRequest — request shape for the terrain backend.
##
## Per spec 20 page contract. A consumer (renderer, collision, nav,
## decoration, AI) submits a request and gets back a TerrainPageResult.
##
## `capabilities` selects which fields the backend computes. Empty
## means no-op; backend should reject. Vocabulary is enforced by
## validate() — new capability strings must be added here AND in the
## spec 20 vocabulary list.
##
## Cache key composition is content-addressed (spec 12): same request
## fields → same key → same cached result.

class_name TerrainPageRequest extends RefCounted


const VALID_CAPABILITIES := [
	"height_gpu",
	"height_cpu",
	"collision_height",
	"slope",
	"nav_traversability",
	"biome_mask_gpu",
	"biome_mask_cpu",
	"drainage_map",
	"flow_direction",
]


var world_xz: Vector2 = Vector2.ZERO  # page origin in world space
var extent_m: float = 256.0           # page side length in meters
var grid_n: int = 256                  # samples per side
var seed: int = 0
var tier: String = "high"
var capabilities: PackedStringArray = PackedStringArray()
var kernel_config_hash: String = ""    # spec 19 kernel config stamp (for cache key)


## Build from a plain Dictionary (test fixtures, JSON payloads).
static func from_dict(d: Dictionary) -> TerrainPageRequest:
	var req := TerrainPageRequest.new()
	if d.has("world_xz"):
		req.world_xz = d["world_xz"]
	if d.has("extent_m"):
		req.extent_m = float(d["extent_m"])
	if d.has("grid_n"):
		req.grid_n = int(d["grid_n"])
	if d.has("seed"):
		req.seed = int(d["seed"])
	if d.has("tier"):
		req.tier = String(d["tier"])
	if d.has("capabilities"):
		req.capabilities = PackedStringArray(d["capabilities"])
	if d.has("kernel_config_hash"):
		req.kernel_config_hash = String(d["kernel_config_hash"])
	return req


## Returns an Array of error strings; empty Array means valid.
func validate() -> Array:
	var errors: Array = []
	if grid_n <= 0:
		errors.append("grid_n must be > 0 (got %d)" % grid_n)
	if extent_m <= 0.0:
		errors.append("extent_m must be > 0 (got %f)" % extent_m)
	if capabilities.is_empty():
		errors.append("capabilities cannot be empty (no-op request)")
	for cap in capabilities:
		if not VALID_CAPABILITIES.has(cap):
			errors.append("unknown capability '%s' (see spec 20 vocabulary)" % cap)
	if tier == "":
		errors.append("tier cannot be empty")
	return errors


## Content-addressed cache key (per spec 12). Capabilities are sorted
## so order doesn't affect the key — same fields → same cache hit.
func cache_key() -> String:
	var sorted_caps := Array(capabilities)
	sorted_caps.sort()
	var inputs := {
		"world_xz_x": world_xz.x,
		"world_xz_y": world_xz.y,
		"extent_m": extent_m,
		"grid_n": grid_n,
		"seed": seed,
		"tier": tier,
		"capabilities": sorted_caps,
		"kernel_config_hash": kernel_config_hash,
	}
	return ContentAddress.compute_stamp(inputs)
