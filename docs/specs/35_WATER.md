# Spec: Water

> Status: draft
> Tier: 2 (world)
> Depends on: 21_TERRAIN_RENDERER, 22_BIOME_CATALOG, 30_ATMOSPHERE,
> 31_LIGHTING_GI, 19_KERNEL_SYSTEM, 33_NAV_EXPORT, 10_STREAMING_BUDGET
> Consumed by: terrain renderer (water surface rendered alongside),
> nav export (water mask), decoration (shoreline placement gates),
> camera (underwater state)

## Purpose

Lakes, rivers, coasts, underwater — the full water system in v1 per
"do it right, full first time." Shader + heuristics, NOT realtime
fluid simulation (cut per inventory).

Critical framing: **engine perf budget ≠ consumer game's perf budget.**
A consumer wizard game has enemies, skill VFX, UI, audio, AI on top of
world rendering. Water perf must leave consumers headroom. Defaults
target the cheap path; high-fidelity opt-in per-water-body.

## Non-goals

- Realtime fluid simulation (heuristic + shader only)
- Ship/boat physics (consumer)
- Underwater cave intersection — caves spec 37 handles cave volumes;
  water spec handles submerged volumes inside caves via the same
  primitives
- Water-on-grass / wet-puddle decals beyond shoreline wetness
  (decoration territory)

## V1 four-phase scope (all in v1)

### Phase A — Lakes (static water bodies)

- Authored or kernel-driven water-surface meshes (one mesh per lake)
- Flat plane shader with normal-map ripples + sun reflection
- Shoreline wetness band on terrain (terrain shader samples water
  proximity, darkens albedo + boosts roughness in N-meter band)
- Fog interaction (underwater fog density different from above-water)
- Bobbing wave shader (vertex offset, low-amplitude sine + noise)

### Phase B — Rivers (flowing water)

- River masks: per-chunk water mask derived from spec 19
  ErosionKernel's `drainage_map` + `flow_accumulation` auxiliary
  outputs (SA-C4.8); cells exceeding a flow-accumulation threshold
  become river cells. Hand-authored splat overrides via spec 22 win
  locally.
- Flow direction map: from spec 19 ErosionKernel's `flow_direction`
  output, precomputed per page
- Flow shader: normal-map scroll along flow direction; foam at high
  gradient (waterfalls + rapids)
- Variable river width along path

### Phase C — Coasts (where water meets land at scale)

- Beach transition zone (terrain albedo blends to sand near sea level)
- Wave shader at shoreline: animated foam line + small breaking-wave
  effect
- Tide-level support (low-priority; configurable static tide range)

### Phase D — Underwater

- Camera-submerged detection (camera Y vs water surface Y)
- Underwater post-process: color shift (blue tint), caustics
  (animated noise), fog density override
- Buoyancy data hook (publishes "water at this XZ at this Y depth")
  for consumer physics
- Surface deformation hooks (consumer-placed floating objects can
  query water-surface offset)

## Reflection technique (tiered + per-body opt-in)

Defaults stay cheap so consumer games have GPU headroom:

| Tier | Default reflection | Opt-in upgrade |
|---|---|---|
| `low` | Cubemap (sky only) | — |
| `medium` | Cubemap | SSR per-body |
| `high` | Cubemap | SSR or Planar per-body |
| `ultra` | SSR | Planar per-body |

**Per-water-body opt-in**: each lake / river / coast in the world
bundle can be tagged `reflection: planar`, `reflection: ssr`, or
`reflection: cubemap` (default). Consumer marks hero water bodies
for planar; gameplay-distant water stays cheap.

This framing matters: planar reflection ~doubles per-frame cost in
the reflection region. Default-planar would eat consumer game budget.
Opt-in keeps the choice local + intentional.

## Water-body definition

`worlds/<world>/water_bodies.json`:

```json
{
  "schema_version": 1,
  "lakes": [
    {
      "name": "altar_lake",
      "polygon": [[x, z], ...],   // 2D polygon footprint
      "surface_y_m": 120.0,
      "depth_m_max": 8.0,
      "reflection": "planar",
      "wave_amplitude_m": 0.1,
      "color_tint": [0.2, 0.4, 0.5]
    }
  ],
  "rivers": [
    {
      "name": "river_main",
      "mask_path": "water/river_main_mask.png",   // optional; OR kernel-derived
      "flow_field_path": "water/river_main_flow.png",   // optional; OR kernel-derived
      "surface_y_offset_from_terrain_m": -0.5,
      "width_m": 12.0,
      "reflection": "cubemap"
    }
  ],
  "coasts": [
    {
      "name": "south_sea",
      "polygon": [...],
      "sea_level_y_m": 0.0,
      "tide_range_m": 0.5,
      "wave_amplitude_m": 0.4,
      "reflection": "ssr"
    }
  ]
}
```

Kernel-derived rivers: terrain spec 19 ErosionKernel can output
drainage networks; rivers automatically fill the low-gradient channels.
Per-world choice: hand-authored masks (smaller worlds) vs kernel
derivation (large procedural worlds).

## Public API (skeleton)

```gdscript
class_name WaterWorld extends Node3D
# Scene component consumers instance

@export var world_bundle_path: String
@export var focus_camera_path: NodePath
@export var quality_tier_override: String = ""

signal water_loaded()
signal camera_entered_water(body_name: String)
signal camera_exited_water()

func is_position_underwater(world_pos: Vector3) -> bool
func get_water_surface_y_at(world_xz: Vector2) -> float  # -INF if no water
func get_buoyancy_force_at(world_pos: Vector3) -> Vector3
func get_flow_direction_at(world_xz: Vector2) -> Vector2  # for rivers
```

## Producer / consumer contract

- **Produces**: rendered water surfaces; underwater post-process state;
  buoyancy + flow data; nav water mask contribution
- **Consumes**: water_bodies.json; ErosionKernel for drainage (when
  kernel-derived); camera position for submerged detection

## Wetness shoreline integration

Terrain shader samples nearest water body distance per fragment. In
the N-meter shoreline band, terrain albedo darkens + roughness drops.
Shader implementation: world-anchored water distance field
(`Texture2DArrayRD` per water body or aggregate per chunk; TBD in
plan doc).

## Dependencies

- `21_TERRAIN_RENDERER` (water rendered alongside; shoreline shader
  hook)
- `22_BIOME_CATALOG` (per-biome water bodies + tide defaults)
- `30_ATMOSPHERE` (sun direction for water shader; underwater fog
  override)
- `31_LIGHTING_GI` (cubemap source from sky)
- `19_KERNEL_SYSTEM` (ErosionKernel for kernel-derived rivers)
- `33_NAV_EXPORT` (water mask contribution)
- `10_STREAMING_BUDGET` (per-body publish: tri count, reflection cost)

## Quality bar

- **Frame budget per water body (default cubemap)**: ≤ 0.3ms
- **Frame budget per SSR-tagged body**: ≤ 1.0ms
- **Frame budget per planar-tagged body**: ≤ 3.0ms (with bounded
  reflection-mesh complexity)
- **Total water budget on high tier**: ≤ 2ms p99 (assumes consumer has
  cubemap default + 1-2 SSR upgrades; planar opt-in is at-your-own-cost)
- Underwater post-process: ≤ 0.5ms p99
- Visual: water reads as water (proper sun glint, normal-map ripples
  legible, foam at appropriate gradients, smooth shore transition)
- World contract validates water_bodies.json; gut covers water-state
  signals; capture tests for visual gates

## Discoverability

- **Entry point**: `WaterWorld` scene component
- **Schema**: `engine/resources/schemas/water_bodies.schema.json`
- **Validator / preflight**: world contract validates polygons inside
  world extent, surface_y values sane, reflection tags valid
- **Example**: `engine/examples/water_example_world/` with a lake +
  a river + a coast
- **Deterministic outputs**: yes — same water_bodies.json + same
  camera position → same surface heights + flow directions

## Open questions

- **Lake polygon authoring**: hand-authored vs auto-derived from
  terrain low points + ErosionKernel drainage basins. Probably both
  supported. Defer auto-derivation to a later sprint; v1 ships hand-
  authored only.
- **Water depth from polygon + surface_y**: simple version assumes
  flat bottom = surface_y - depth_max. Real lakes have variable
  bottoms. Schema slot for depth heightmap; defer implementation.
- **Multiple connected water bodies**: a river feeding a lake feeding
  a sea — visual / nav continuity. Plan-doc detail.
- **Ice / frozen water**: alpine lakes in winter. Schema slot for
  `frozen: bool`; rendering swap to ice shader. Defer.

## References

- W4 wishlist: water as 4-phase progression (lakes / rivers / coasts
  / underwater)
- Industry water shaders: Crytek's CryEngine ocean, RDR2 river
  rendering as reference for the layered shader approach

## Revision history

- 2026-05-16: initial draft
