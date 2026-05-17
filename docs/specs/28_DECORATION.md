# Spec: Decoration

> Status: draft
> Tier: 1 (core)
> Depends on: 07_JOB_SYSTEM, 08_SPATIAL_INDEX, 09_ASYNC_ASSET_STREAMING,
> 10_STREAMING_BUDGET, 11_CHANGE_BROADCAST, 22_BIOME_CATALOG,
> 27_LOD_BAKE, 13_QUALITY_TIERS
> Consumed by: terrain renderer (rendered alongside terrain); world contract

## Purpose

Per-chunk placement of meshes (rocks, props, structures, plants,
bones, etc.) on the terrain. Deterministic Poisson-disk scatter with
slope / biome / surface-slot / orientation / clustering /
vertical-layering / exclusion-zone rules. Author overrides
(handcrafted instances + zones for hand-authored set-pieces).
Per-instance LOD with hysteresis + dither cross-fade.

W4.1 shipped R1-R14 sprint by sprint. **W5 builds fresh on Tier 0
primitives** rather than copying W4 runtime — the W4 architecture
had a 4-system tangle that produced real bugs (R14a/b/c crisis).
The W4 *learnings* carry over as design references; the *code* is
rebuilt against the Job system, spatial index, async asset streaming,
and change broadcast.

## Non-goals

- NPC / animal / wildlife placement (consumer responsibility per inventory)
- Foliage trees (foliage spec 29; trees are NOT decoration, they
  have parametric branches)
- Collision shape generation (deferred to a later sprint; W4 G1 stub)
- Wind shader on decoration (deferred to a later sprint; W4 H1 stub)

## V1 feature set

In scope for v1 (the 2-biome demo):

| Feature | W4 sprint | W5 v1 |
|---|---|---|
| Per-chunk Poisson-disk scatter (deterministic) | R1+R2 | ✅ |
| Per-biome decoration palettes (YAML) | R2 | ✅ |
| Author-override zones + handcrafted instances | R3 | ✅ |
| Per-tier knobs (density, LOD distances, max visible) | R4 | ✅ |
| Schema + preflight (LLM-driveability) | R6 | ✅ |
| Slope range, surface-slot, biome-dominance, orientation | R7 | ✅ |
| Clustering (clump / ring / line / patch) | R8 | ✅ |
| Exclusion zones (all / categories / subjects) | R9 | ✅ |
| Vertical layering (floor / understory / canopy) | R13 | ✅ |
| Kernel terrain source adapter | R2.1 | ✅ |
| Per-instance LOD with hysteresis | R14a-c | ✅ |
| Dither cross-fade (LOD-pop fix) | R15 (W4 deferred) | ✅ **ships in W5 v1** |

Deferred for post-v1 sprints:

| Feature | W4 sprint | W5 status |
|---|---|---|
| Hot-reload of palettes | R5 | Deferred to dev-loop level 3 (spec 18) |
| Dependency rules ("moss on rocks") | R10 | Deferred — needs cross-instance queries |
| Climate gating | R11 | Deferred — depends on weather spec |
| Directional placement (cardinal / into-hillside) | R12 | Deferred — nice but not blocking |
| Per-instance collision shapes | G1 | Deferred — Tier 2 / Phase 7+ |
| Wind shader sway | H1 | Deferred — Tier 2 / Phase 7+ |

## Architecture (built fresh on Tier 0)

```
┌──────────────────────────────────────────────────┐
│ Decoration generator (Python; offline bake)      │
│   pipeline/decoration/                            │
│   • Poisson scatter per chunk                     │
│   • Rule evaluation (slope/biome/slot/orient)     │
│   • Clustering / vertical layering / zones         │
│   • Outputs deterministic blob per chunk          │
└────────────────┬─────────────────────────────────┘
                 │ .bin per chunk → worlds/<world>/decorations/
                 ▼
┌──────────────────────────────────────────────────┐
│ Decoration runtime (GDScript)                     │
│   engine/scripts/decoration/                      │
│   • DecorationManager — residency + budget        │
│   • ChunkDecorationLayer — per-chunk MMs          │
│   • DecorationBlobLoader — blob format reader     │
│   • DecorationMeshCache — through AssetStream    │
│   • LOD pass — per-instance, hysteresis + dither  │
└────────────────┬─────────────────────────────────┘
                 │
                 ▼
   Job system + spatial index + async asset streaming
   + streaming budget + change broadcast (Tier 0)
```

The runtime is decomposed up front (no god-files). Spatial index used
for instance LOD pass + zone lookups. Async asset streaming used for
mesh load. Change broadcast subscribed to for zone edit invalidation.
Streaming budget published into for instance count + draw call cost.

## Public API (skeleton)

```gdscript
# engine/scenes/components/decoration_world.tscn — consumer instances this
class_name DecorationWorld extends Node3D

@export var world_bundle_path: String
@export var focus_camera_path: NodePath
@export var quality_tier_override: String = ""

signal instance_count_changed(total: int)

func get_resident_chunk_count() -> int
func get_total_visible_instances() -> int
func get_debug_state() -> Dictionary
```

```python
# pipeline.decoration.bake — offline generator CLI
python -m world5.decoration.bake --world worlds/two_biome_demo --seed 42
```

## Blob format

Per-chunk binary file `worlds/<world>/decorations/<cx>_<cz>.bin`:

```
magic                 8 bytes  b"W5DECv1\0"
schema_version        u32       = 1
header                ...       chunk_x, chunk_z, source_kind, seed,
                                 generator_revision, biome catalog hash,
                                 material hash, w5_version, quality_tier,
                                 decoration_revision, hash of palettes,
                                 hash of zones, hash of kernel config

  # SA-S3.15: decoration_revision = sha256(
  #   generator_module_version || per_biome_palette_yaml_sha ||
  #   zones_json_sha || kernel_config_sha
  # ) computed at bake time. Loader detects "rule files changed since
  # this blob was baked" → triggers rebake. Distinct from
  # generator_revision (the generator code version).
mesh_id_table         u16 count + lpstr * count
instance_count        u32
instances             [u16 mesh_idx, u16 _pad,
                       f32 x, f32 y, f32 z,
                       f32 qx, f32 qy, f32 qz, f32 qw, f32 scale]
                      * count  (40 bytes each, 4-byte aligned — audit M4
                                fix: previous "34 bytes" was off-by-6;
                                32-bit alignment after u16 mesh_idx
                                requires u16 pad)
```

V1 ships only blob schema v1 (no auto-upgrade complexity). Migration
spec 17 handles future schema bumps.

## Per-instance LOD with dither

Each tick (configurable interval, default 0.2s):

1. **Movement gate**: skip if camera moved < `lod_pass_min_movement_m`
2. **Near-chunks-only filter**: only re-classify chunks within
   `lod_far_m + chunk_margin_m` of camera
3. For each instance in scope: compute horizontal distance to camera,
   classify into LOD bucket (close/mid/far/culled) with hysteresis
4. For each (mesh_id, lod_bucket) MultiMesh whose membership changed:
   rebuild via bulk `multimesh.buffer` write
5. **Dither cross-fade** (R15 in W5 v1): during ±N meters of a LOD
   boundary, the outgoing tier renders with screen-door alpha (stipple
   pattern), incoming tier fades in alpha-cutout. Eliminates the
   visible "pop." Shader supports it via per-instance custom_data alpha.

Per-instance "next threshold" cache + spatial index integration avoids
re-walking every instance per pass.

## Author overrides

`worlds/<world>/decoration_overrides.json`:

```json
{
  "schema_version": 1,
  "overrides": [
    {
      "name": "altar_grove",
      "bounds": {"x0": -300, "z0": -300, "x1": -200, "z1": -200},
      "mode": "hybrid",
      "density_mult": 0.5,
      "instance_overrides": [
        {"mesh": "structures/altar_stone_01", "pos": [-250, 0, -250], "rot_y_deg": 0, "scale": 1.4}
      ]
    },
    {
      "name": "bone_field",
      "bounds": {...},
      "mode": "handcrafted",
      "instances_file": "decorations/bone_field_handauthored.json"
    },
    {
      "name": "village_clearing",
      "bounds": {...},
      "mode": "exclude",
      "scope": "all"
    }
  ]
}
```

Modes: `procedural` (default, run rules), `handcrafted` (read file,
no procedural in that bounds), `hybrid` (procedural + overrides),
`exclude` (no decoration in bounds).

## Producer / consumer contract

- **Produces** (pipeline): per-chunk decoration blobs (deterministic
  given inputs); preflight reports
- **Produces** (runtime): rendered MultiMeshInstances; streaming
  budget publish; change broadcast subscriptions
- **Consumes**: biome catalog (per-biome palettes), LOD bake output
  (mesh chains), world contract preflight

## Dependencies

- `07_JOB_SYSTEM` (async chunk bring-up, blob load, mesh resolution)
- `08_SPATIAL_INDEX` (LOD pass, zone lookups)
- `09_ASYNC_ASSET_STREAMING` (mesh load via `request_mesh`)
- `10_STREAMING_BUDGET` (publish instance count + draw calls)
- `11_CHANGE_BROADCAST` (subscribe to `decoration_zone` source for
  zone-edit invalidation; publish on runtime placement edits)
- `22_BIOME_CATALOG` (per-biome decoration palette refs)
- `27_LOD_BAKE` (mesh chain availability)
- `13_QUALITY_TIERS` (per-tier density / LOD distances / max visible)

## Quality bar

- Per-chunk blob bake: ≤ 500ms at high tier
- Runtime bring-up of a fresh chunk: ≤ 50ms (uses async streaming;
  visible "fade in via dither" acceptable, hard pop forbidden)
- LOD pass + MMI draws combined: ≤ 0.8 ms per frame at `high` tier
  (authorized by `X_FRAME_BUDGET.md`); LOD pass at 5Hz default rate
- Zero visible LOD pops at any walking speed (dither makes it
  perceptually continuous)
- 100% pytest coverage of generator + GDScript-side gut coverage of
  runtime
- Preflight validates: every palette mesh ref exists in LOD manifest,
  zones bounds in world extent, schema sane

## Discoverability

- **Entry point**: `python -m world5.decoration.bake` (offline);
  `DecorationWorld` scene component (runtime)
- **Schema**: blob format above + `decoration_overrides.json` schema +
  per-biome palette YAML schema (each in `engine/resources/schemas/`)
- **Validator / preflight**: world contract runs decoration preflight
  per spec 14
- **Example**: `engine/examples/decoration_example/` shows palette +
  zones + runtime scene
- **Deterministic outputs**: yes — same seed + same palette + same
  zones + same kernel + same revision → byte-identical blob

## Open questions

- **Dither cross-fade band width**: probably ±5m around each LOD
  boundary. Defer to plan doc tuning.
- **Foliage co-residence**: DECIDED (audit S8): foliage runs its
  OWN placement (spec 29). Decoration and foliage coordinate via
  (a) shared spatial index (spec 08), and (b) a shared
  exclusion-zone broadcast on ChangeBroadcast source
  `placement_exclusion`. Foliage publishes its trunk footprints as
  exclusion zones; decoration subscribes and skips its scatter
  within them (and vice versa for large structures that need to
  exclude foliage). Vertical layering rules in this spec still apply
  for non-foliage canopy items (vines, hanging moss).
- **Runtime placement edits (persistence)**: when persistence ships
  (spec 39), runtime adds-via-API placements publish
  `change_broadcast.publish(region, "decoration_runtime_add")`.
  Schema slot for it; implementation in persistence sprint.

## References

- W4 retrospective + decoration plan 19 (R14 sprint)
- W4 memory entries: `gdscript_packed_array_dict_value_type` (the bug
  fixed in R14b — built-fresh avoids it via gut testing in spec 06)
- W4 decoration spec docs at `world 4/docs/plans/decoration/`

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (C8, M4, S8). Renamed
  `decoration_zones.json` → `decoration_overrides.json` to match
  spec 39's unified envelope. Fixed instance byte size 34 → 40 (audit
  M4: previous size omitted alignment pad). Committed foliage-decoration
  placement seam (audit S8): each runs own placement, coordinates via
  shared spatial index + `placement_exclusion` broadcast.
- 2026-05-17: outside audit (OA-C4) — fixed envelope key `"zones"` →
  `"overrides"` to actually match spec 39 (the rename was only the
  filename; the JSON example still showed `"zones"` so a consumer
  reading spec 28 alone would have produced invalid input).
