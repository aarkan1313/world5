## ClipmapDispatch — per-frame ring update.
##
## Per spec 21 module decomposition. Each frame:
##   1. Snap every ring's center to its own cell grid (via ClipmapRing.set_center)
##   2. Compute per-ring morph-band factor for the vertex shader to
##      smoothly blend ring N into ring N+1's geometry near boundaries
##
## Does NOT push uniforms — MaterialPipeline (4.4.c) owns that. This
## class is the math + state-update layer.

class_name ClipmapDispatch extends RefCounted


## Default morph-band fraction (per spec 21 clipmap parameters table).
## Locked-in value pending Phase 4.6 visual validation.
const DEFAULT_MORPH_BAND_FRACTION: float = 0.16


## Update all rings to follow the camera.
func update(rings: Array, camera_world_pos: Vector3) -> void:
	var camera_xz: Vector2 = Vector2(camera_world_pos.x, camera_world_pos.z)
	for ring in rings:
		# ring is a ClipmapRing (untyped Array — GDScript can't
		# constrain Array element types via class_name)
		ring.set_center(camera_xz)


## Compute per-ring morph factor in [0, 1].
##
## 0.0 = ring is fully "current LOD" (camera well inside the stable region)
## 1.0 = ring is fully morphed to next LOD (camera at or past the ring boundary)
##
## Uses Chebyshev distance (max of |dx|, |dz|) because clipmap rings
## are squares, not circles. The band starts at half_extent * (1 -
## band_frac) and ends at half_extent. Inside the band, morph
## linearly ramps 0 → 1.
func compute_morph_factor(camera_xz: Vector2, ring_center: Vector2,
		half_extent_m: float, band_frac: float = DEFAULT_MORPH_BAND_FRACTION
		) -> float:
	var delta: Vector2 = camera_xz - ring_center
	var cheb_dist: float = max(abs(delta.x), abs(delta.y))
	var band_start: float = half_extent_m * (1.0 - band_frac)
	var band_width: float = half_extent_m - band_start
	if cheb_dist <= band_start:
		return 0.0
	if cheb_dist >= half_extent_m or band_width <= 0.0:
		return 1.0
	return (cheb_dist - band_start) / band_width
