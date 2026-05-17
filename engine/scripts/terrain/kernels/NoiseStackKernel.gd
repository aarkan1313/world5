## NoiseStackKernel — fBm height kernel config.
##
## Per spec 19. Wraps the kernel parameters that drive the GPU
## compute backend (engine/shaders/terrain_page_gen.glsl) AND the
## Python reference (pipeline/world5/kernels/noise_stack.py). The
## three implementations must agree on the same config.
##
## A NoiseStackKernel is config-only — it doesn't sample anything
## itself. Sampling happens in GpuTerrainBackend (GPU compute) or
## in the Python reference (parity tests). This separation matches
## spec 19's "kernel = pure function" intent: the params are the
## function; the sampler is implementation.

class_name NoiseStackKernel extends RefCounted


## fBm octave count. More = more detail, more cost. Default 6 hits
## the W4-validated sweet spot for ~50m height range.
var octaves: int = 6
## Base frequency in cycles/meter. Default 1/512 = ~512m base
## wavelength.
var frequency: float = 1.0 / 512.0
## Per-octave frequency multiplier. 2.0 = octave doubling (standard).
var lacunarity: float = 2.0
## Per-octave amplitude multiplier. 0.5 = standard halving.
var gain: float = 0.5
## Peak-to-peak amplitude in meters. Default 50m matches a typical
## hill range.
var amplitude: float = 50.0


## Build from a Dictionary; missing keys keep defaults.
static func from_dict(d: Dictionary) -> NoiseStackKernel:
	var k := NoiseStackKernel.new()
	if d.has("octaves"):
		k.octaves = int(d["octaves"])
	if d.has("frequency"):
		k.frequency = float(d["frequency"])
	if d.has("lacunarity"):
		k.lacunarity = float(d["lacunarity"])
	if d.has("gain"):
		k.gain = float(d["gain"])
	if d.has("amplitude"):
		k.amplitude = float(d["amplitude"])
	return k


func to_dict() -> Dictionary:
	return {
		"octaves": octaves,
		"frequency": frequency,
		"lacunarity": lacunarity,
		"gain": gain,
		"amplitude": amplitude,
	}


## Returns an Array of error strings; empty Array means valid.
func validate() -> Array:
	var errors: Array = []
	if octaves <= 0:
		errors.append("octaves must be > 0 (got %d)" % octaves)
	if octaves > 16:
		errors.append("octaves capped at 16 (got %d)" % octaves)
	if frequency <= 0.0:
		errors.append("frequency must be > 0 (got %f)" % frequency)
	if lacunarity <= 1.0:
		errors.append("lacunarity must be > 1.0 (got %f)" % lacunarity)
	if gain <= 0.0 or gain >= 1.0:
		errors.append("gain must be in (0, 1) (got %f)" % gain)
	if amplitude < 0.0:
		errors.append("amplitude must be >= 0 (got %f)" % amplitude)
	return errors


## Content-addressed config hash. Same config -> same hash, used in
## TerrainPageRequest.kernel_config_hash for cache + cross-impl
## consistency check (TB-REV-S3).
func config_hash() -> String:
	return ContentAddress.compute_stamp(to_dict())
