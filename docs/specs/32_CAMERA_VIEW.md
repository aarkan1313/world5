# Spec: Camera + View

> Status: draft
> Tier: 1 (core)
> Depends on: 13_QUALITY_TIERS, 20_TERRAIN_BACKEND, 21_TERRAIN_RENDERER
> Consumed by: consumer game scenes; terrain renderer (consumes camera
> position for streaming + LOD focus)

## Purpose

Single 3D walk-camera primitive for W5 runtime. WASD + mouse-look.
Quality-tier aware (FOV, far plane, eye height).

Per inventory decision: **runtime is 3D-only**. No iso/topdown
runtime view-switching. 2.5D/topdown become offline bake recipes
(Tier 3 spec 42), not runtime modes.

W4.1's `AnchorCameraRig.gd` had walk/iso/topdown modes — much
simpler in W5 because iso/topdown are deleted from runtime.

## Non-goals

- Iso/topdown runtime view modes (Tier 3 bake recipes own these)
- Cinematic camera scripting (consumer concern; engine ships the
  primitive, consumer wires sequences)
- VR / first-person-XR cameras (not in W5 scope)
- Smooth zoom from topdown to walk (Crimson-Desert-style; WISHLIST,
  defer)

## V1 feature set

- WASD movement
- Mouse-look (yaw + pitch)
- Quality-tier-aware FOV, far plane, near plane, eye height
- Auto eye-height adjustment (camera stays on terrain surface +
  configurable eye height; uses terrain backend's sample_height_at)
- Sprint / crouch toggle (consumer-extensible; engine ships defaults)
- Optional fly mode (gameplay-toggleable; engine ships disabled by
  default)
- Camera position publish (terrain renderer + decoration + foliage
  consume for streaming + LOD focus)

## Public API (skeleton)

```gdscript
# engine/scenes/components/walk_camera.tscn
class_name WalkCamera extends Node3D

@export var move_speed_mps: float = 5.0
@export var sprint_mult: float = 2.0
@export var eye_height_m: float = 1.8
@export var fov: float = 70.0
@export var far_plane_m: float = 0.0  # 0 = use quality tier default
@export var mouse_sensitivity: float = 0.002
@export var fly_mode: bool = false
@export var terrain_world_path: NodePath  # to sample ground height

signal moved(world_xz: Vector2)

func teleport_to(world_xz: Vector2) -> void
func get_camera_3d() -> Camera3D
```

Consumer instances the scene component, points at the terrain
world, gets walk-around behavior. Quality tier auto-applied unless
exports override.

## Producer / consumer contract

- **Produces**: camera position over time; `moved` signal for streaming
  consumers; the active `Camera3D` node
- **Consumes**: terrain world's `sample_height_at` for eye-height
  adjustment; quality tier knobs for defaults

## Dependencies

- `13_QUALITY_TIERS` (FOV, far plane, eye-height defaults)
- `20_TERRAIN_BACKEND` (`sample_height_at` source via `height_cpu`
  capability; SA-M4.4: was incorrectly attributed to spec 21)
- `21_TERRAIN_RENDERER` (camera tells renderer where to focus
  streaming; the sample_height_at convenience wrapper lives on
  TerrainWorld but the data is backend-owned)

## Quality bar

- Camera input → response: ≤ 1 frame
- Eye-height sampling: ≤ 100µs per frame
- No camera clipping into terrain at normal walking speed
- Smooth mouse-look (no jitter, no pitch lock at exactly ±90°)
- gut coverage of input + movement; capture-based test that camera
  follows terrain correctly

## Discoverability

- **Entry point**: `WalkCamera` scene component
- **Schema**: GDScript exports listed above
- **Validator / preflight**: none beyond scene-load (camera is
  trivial)
- **Example**: `demo/scenes/walking_demo.tscn` instances `WalkCamera`
- **Deterministic outputs**: input → position is deterministic; no
  random elements

## Open questions

- **Collision**: should the camera itself have a capsule body for
  collision, or just clamp to terrain height? W4 had `PlayerBody.gd`
  as a separate test-harness CharacterBody3D. v1 spec'd as
  terrain-clamp only (simpler); collision body is consumer concern.
- **Camera shake / kick (gameplay events)**: schema slot only; consumer
  drives.
- **Multi-cam scenes**: cinematic sequences may want multiple cameras
  with switching. v1 supports one active WalkCamera; consumer manages
  multi-cam.

## References

- W4 `scripts/AnchorCameraRig.gd` (walk-mode logic carries over;
  iso/topdown logic is deleted for W5)

## Revision history

- 2026-05-16: initial draft
