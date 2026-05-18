## DemFeatureKernel — DEM-derived feature extraction config.
##
## Per spec 19 §"Kernel types shipped in v1" item 3. Wraps the kernel
## parameters that drive the runtime DEM feature pipeline AND the
## Python reference (pipeline/world5/kernels/dem_feature.py).
##
## A DemFeatureKernel is config-only — it doesn't sample anything
## itself. Execution happens via:
## - Bake-route v1 (Sprint 3): pipeline-baked feature PNGs loaded by
##   DemSource.gd; runtime samples baked features per page.
## - GPU compute-route v2 (Sprint 4): GLSL compute extracts features
##   per page on the fly; tile pyramid streams DEM tiles in/out as
##   the camera moves (procedural infinite).
##
## Mirrors NoiseStackKernel.gd + ErosionKernel.gd pattern.

class_name DemFeatureKernel extends RefCounted


## Valid feature modes (must match the Python ref).
const MODE_RIDGE_EMPHASIS := "ridge_emphasis"
const MODE_DRAINAGE_ACCUMULATION := "drainage_accumulation"
const MODE_SLOPE_DEG := "slope_deg"
const MODE_ASPECT_DEG := "aspect_deg"

const VALID_MODES := [
	MODE_RIDGE_EMPHASIS,
	MODE_DRAINAGE_ACCUMULATION,
	MODE_SLOPE_DEG,
	MODE_ASPECT_DEG,
]


## Bundle-local DEM source ID (declared in `<bundle>/dem/<id>.json`
## sidecar per dem_source.schema.json). Resolved at runtime by
## DemSource.from_bundle(bundle_path, source).
var source: String = ""
## Feature mode to extract. v1 supports one mode per stage; multiple
## modes via multiple chain stages (each producing its own field that
## a downstream stage can read).
var mode: String = MODE_RIDGE_EMPHASIS
## Strength of the feature's contribution to the chain output, in [0, 1].
## Composer dispatches the stage's blend via this knob; specific
## semantics depend on the downstream stage (e.g. multiplying ridge
## emphasis into height before erosion).
var strength: float = 0.7
## Gaussian smoothing σ (in source-DEM cells) applied before computing
## curvature. Lower = sharper ridges, more noise. Higher = smoother
## ridges. Matches the Python reference default.
var ridge_smooth_sigma_cells: float = 2.0
## Deterministic seed (reserved for future stochastic variants;
## current ridge/drainage/slope/aspect math is deterministic).
var seed: int = 42


static func from_dict(d: Dictionary) -> DemFeatureKernel:
	var k := DemFeatureKernel.new()
	if d.has("source"):
		k.source = String(d["source"])
	if d.has("mode"):
		k.mode = String(d["mode"])
	if d.has("strength"):
		k.strength = float(d["strength"])
	if d.has("ridge_smooth_sigma_cells"):
		k.ridge_smooth_sigma_cells = float(d["ridge_smooth_sigma_cells"])
	if d.has("seed"):
		k.seed = int(d["seed"])
	return k


func to_dict() -> Dictionary:
	return {
		"source": source,
		"mode": mode,
		"strength": strength,
		"ridge_smooth_sigma_cells": ridge_smooth_sigma_cells,
		"seed": seed,
	}


## Returns an Array of error strings; empty Array means valid.
func validate() -> Array:
	var errors: Array = []
	if source == "":
		errors.append("source is required (bundle-local DEM ID)")
	if not VALID_MODES.has(mode):
		errors.append("mode must be one of %s (got '%s')" % [VALID_MODES, mode])
	if strength < 0.0 or strength > 1.0:
		errors.append("strength must be in [0, 1] (got %f)" % strength)
	if ridge_smooth_sigma_cells <= 0.0:
		errors.append("ridge_smooth_sigma_cells must be > 0 (got %f)" %
			ridge_smooth_sigma_cells)
	return errors


## Content-addressed config hash. Same config → same hash.
## Note: the hash does NOT include the DEM source's content hash —
## that's the DemSource's responsibility. Together they produce the
## full content-addressed cache key per spec 12.
func config_hash() -> String:
	return ContentAddress.compute_stamp(to_dict())
