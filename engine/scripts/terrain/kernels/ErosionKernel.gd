## ErosionKernel — hydraulic + thermal erosion config.
##
## Per spec 19 §"Kernel types shipped in v1" item 2. Wraps the kernel
## parameters that drive the GPU compute backend
## (engine/shaders/terrain_erosion.glsl) AND the Python reference
## (pipeline/world5/kernels/erosion.py). The two implementations must
## agree on the same config — parity tested in
## `tests/integration/test_erosion_parity_real_device.gd`.
##
## An ErosionKernel is config-only — it doesn't sample anything itself.
## Execution happens in GpuTerrainBackend (GPU compute, ping-pong
## hydraulic + thermal passes) or in the Python reference (parity tests).
## This separation matches spec 19's "kernel = pure function" intent
## and mirrors NoiseStackKernel.gd.
##
## Hydraulic pass (Mei et al. 2007): water grid + sediment transport +
## dissolve/deposit. Thermal pass (Musgrave/Kolb): angle-of-repose
## slope diffusion. Iterations interleaved per the rules in
## `pipeline/world5/kernels/erosion.py` (Python reference docstring).

class_name ErosionKernel extends RefCounted


## Hydraulic step count. Higher = more carving. Mei 2007 + Phase 5.7
## tuning: 50-200 typical, 400 for the walking_demo's visible eroded
## look. Cap matches schema (1-1000).
var iterations: int = 50
## Water added per cell per hydraulic step (m/iter).
var rain_rate: float = 0.012
## Fraction of water evaporating per step. Mei 2007 default range:
## 0.005-0.05.
var evaporation: float = 0.015
## Max sediment a unit of flowing water can carry (Mei 2007 Kc).
var sediment_capacity: float = 0.10
## Fraction of capacity-deficit dissolved per step (capacity > sediment).
var dissolve_rate: float = 0.30
## Fraction of capacity-excess deposited per step (sediment > capacity).
var deposit_rate: float = 0.30
## Slope floor for capacity calc (avoids zero-capacity on perfectly
## flat regions — water still moves there but doesn't carve).
var min_slope: float = 0.005
## Gravity constant (m/s²). Scales velocity in capacity calc; ratio-
## only matters since we're in non-dimensional units.
var gravity: float = 9.81
## Total thermal slump steps interleaved with hydraulic. Set to 0 to
## disable thermal entirely.
var thermal_iterations: int = 50
## Angle of repose in degrees. Slopes steeper than this trigger
## material slump in the thermal pass.
var talus_angle_deg: float = 30.0
## Fraction of slope excess moved per thermal step.
var talus_rate: float = 0.25
## Deterministic seed (forwarded to GPU compute path; not used by the
## current pure-deterministic algorithm but reserved for future
## stochastic variants).
var seed: int = 42


## Build from a Dictionary; missing keys keep defaults.
static func from_dict(d: Dictionary) -> ErosionKernel:
	var k := ErosionKernel.new()
	if d.has("iterations"):
		k.iterations = int(d["iterations"])
	if d.has("rain_rate"):
		k.rain_rate = float(d["rain_rate"])
	if d.has("evaporation"):
		k.evaporation = float(d["evaporation"])
	if d.has("sediment_capacity"):
		k.sediment_capacity = float(d["sediment_capacity"])
	if d.has("dissolve_rate"):
		k.dissolve_rate = float(d["dissolve_rate"])
	if d.has("deposit_rate"):
		k.deposit_rate = float(d["deposit_rate"])
	if d.has("min_slope"):
		k.min_slope = float(d["min_slope"])
	if d.has("gravity"):
		k.gravity = float(d["gravity"])
	if d.has("thermal_iterations"):
		k.thermal_iterations = int(d["thermal_iterations"])
	if d.has("talus_angle_deg"):
		k.talus_angle_deg = float(d["talus_angle_deg"])
	if d.has("talus_rate"):
		k.talus_rate = float(d["talus_rate"])
	if d.has("seed"):
		k.seed = int(d["seed"])
	return k


func to_dict() -> Dictionary:
	return {
		"iterations": iterations,
		"rain_rate": rain_rate,
		"evaporation": evaporation,
		"sediment_capacity": sediment_capacity,
		"dissolve_rate": dissolve_rate,
		"deposit_rate": deposit_rate,
		"min_slope": min_slope,
		"gravity": gravity,
		"thermal_iterations": thermal_iterations,
		"talus_angle_deg": talus_angle_deg,
		"talus_rate": talus_rate,
		"seed": seed,
	}


## Returns an Array of error strings; empty Array means valid.
## Validation bounds match erosion.schema.json.
func validate() -> Array:
	var errors: Array = []
	if iterations < 1:
		errors.append("iterations must be >= 1 (got %d)" % iterations)
	if iterations > 1000:
		errors.append("iterations capped at 1000 (got %d)" % iterations)
	if rain_rate <= 0.0:
		errors.append("rain_rate must be > 0 (got %f)" % rain_rate)
	if evaporation < 0.0 or evaporation > 1.0:
		errors.append("evaporation must be in [0, 1] (got %f)" % evaporation)
	if sediment_capacity <= 0.0:
		errors.append("sediment_capacity must be > 0 (got %f)" % sediment_capacity)
	if dissolve_rate < 0.0 or dissolve_rate > 1.0:
		errors.append("dissolve_rate must be in [0, 1] (got %f)" % dissolve_rate)
	if deposit_rate < 0.0 or deposit_rate > 1.0:
		errors.append("deposit_rate must be in [0, 1] (got %f)" % deposit_rate)
	if min_slope < 0.0:
		errors.append("min_slope must be >= 0 (got %f)" % min_slope)
	if gravity <= 0.0:
		errors.append("gravity must be > 0 (got %f)" % gravity)
	if thermal_iterations < 0:
		errors.append("thermal_iterations must be >= 0 (got %d)" % thermal_iterations)
	if talus_angle_deg < 0.0 or talus_angle_deg > 89.0:
		errors.append("talus_angle_deg must be in [0, 89] (got %f)" % talus_angle_deg)
	if talus_rate < 0.0 or talus_rate > 1.0:
		errors.append("talus_rate must be in [0, 1] (got %f)" % talus_rate)
	return errors


## Content-addressed config hash. Same config → same hash; used in
## chain hashing for cache + cross-impl consistency (matches the
## Python reference's hashing via ContentAddressStore).
func config_hash() -> String:
	return ContentAddress.compute_stamp(to_dict())
