# Spec: Terrain Renderer

> Status: draft (BLOCKED on `15a_RENDERER_DECISION.md` for primitive choice)
> Tier: 1 (core)
> Depends on: 15_RENDERER_RESEARCH_BRIEF (output), 20_TERRAIN_BACKEND, 22_BIOME_CATALOG, 23_MATERIALS_PBR, 24_GROUND_VARIETY, 30_ATMOSPHERE, 31_LIGHTING_GI
> Consumed by: every visible W5 scene

## Purpose

The runtime that displays a continuous, streamed heightfield world.
The largest visible system in W5. Consumes terrain backend pages,
biome catalog, material arrays, lighting recipes; produces the lit,
LOD'd, multi-biome 3D world the player walks through.

This spec is **deliberately a skeleton** because the renderer
*primitive* (clipmap vs virtual texturing vs nanite-style vs hybrid)
is decided by spec 15's research sprint. Implementation detail goes
in the plan doc after that decision.

W4.1's `ClipmapWorld.gd` was 3900 lines and a single god-file. W5
must avoid that — the renderer is decomposed into multiple modules
per the audit recommendation, even before the primitive is decided.

## Non-goals

- Picking the renderer primitive (that's spec 15)
- 2.5D/topdown runtime view modes (Tier 3 bake recipes)
- Skybox / atmosphere rendering (delegated to atmosphere spec)
- Lighting beyond consuming the lighting recipe contract
- Decoration rendering (delegated to decoration runtime)
- Water / weather / cave rendering (Tier 2 systems with their own
  specs)

## Module decomposition (regardless of primitive)

```
engine/scripts/terrain/
├── renderer/                # the primitive-specific rendering loop
├── streaming/               # page bring-up / tear-down / cache
├── material/                # PBR / variant / surface-slot binding
├── diagnostics/             # debug overlays, profilers, capture probes
└── TerrainWorld.gd          # composer / public API; thin
```

Even before the primitive is decided, this decomposition is locked.
Whatever the renderer ends up being, it stays decomposed; no
3900-line god-file.

## Public API (skeleton)

```gdscript
class_name TerrainWorld extends Node3D
# The main scene component consumers instance

@export var world_bundle_path: String   # "res://worlds/two_biome/"
@export var camera_path: NodePath        # the camera to follow
@export var quality_tier_override: String = ""   # default: QualityTiers current

signal world_loaded()
signal world_unloaded()
signal full_detail_ready()
signal page_loaded(world_xz: Vector2)
signal page_unloaded(world_xz: Vector2)

func is_full_detail_ready() -> bool
func get_resident_pages() -> Array[Vector2]
func sample_height_at(world_xz: Vector2) -> float
func get_debug_state() -> Dictionary
```

Consumer instances `TerrainWorld`, points at a world bundle, gets a
streamed 3D world. Everything else is internal.

## Producer / consumer contract

- **Produces**: a 3D scene tree of rendered terrain; signals on
  lifecycle events; published streaming budget usage.
- **Consumes**: a world bundle (validated by world contract);
  terrain backend pages; lighting recipe; atmosphere profile;
  material arrays.

## Dependencies (skeleton — refined when primitive chosen)

- `15_RENDERER_RESEARCH_BRIEF` output (primitive choice)
- `20_TERRAIN_BACKEND` (page contract consumed)
- `22_BIOME_CATALOG` (per-biome material binding)
- `23_MATERIALS_PBR` (material array shape)
- `24_GROUND_VARIETY` (variety system integration)
- `30_ATMOSPHERE` (sky, fog, haze)
- `31_LIGHTING_GI` (lighting recipe applied)
- `07_JOB_SYSTEM` + `09_ASYNC_ASSET_STREAMING` + `10_STREAMING_BUDGET`
  + `11_CHANGE_BROADCAST` (foundation primitives)

## Quality bar

- Terrain renderer geometry + draws: ≤ 2.0 ms per frame at `high`
  tier (authorized by `X_FRAME_BUDGET.md`)
- 60fps p99 on RTX 3060/4060 at `high` tier with default 2-biome demo
- Zero hitches > 33ms during normal walk-mode movement
- Cold start: full-detail world ready in < 2s on target hardware
- Visible-LOD-pop ≤ "subtle on hard transitions" (real bar set by
  dither/cross-fade spec; the renderer must support being driven by
  it)
- Visual quality: at least matches Genshin-tier open-world terrain
  (pillar 1 bar)
- **GPU/CPU thread compliance verified per spec 08a** (SA-S3.3):
  all RenderingDevice work goes through GpuJob; no
  RenderingDevice calls from WorkerThreadPool; all GPU resources
  registered with GpuResourceTracker
- No "god file" — `TerrainWorld.gd` ≤ 800 lines (SA-S3.4: relaxed
  from 500; composer realistically needs signal wiring + setup/
  teardown); max single module file ≤ 1500 lines (relaxed from 1000
  for same reason). The structural rule stands: composer is
  delegation only, helpers live in modules.

## Discoverability

- **Entry point**: `engine/scenes/components/terrain_world.tscn`
  (instance + configure); `TerrainWorld` class
- **Schema**: world bundle structure (per spec 14 world contract);
  `TerrainWorld` exports listed above
- **Validator / preflight**: world contract validates the bundle;
  `is_full_detail_ready()` signal verifies ready state
- **Example**: `demo/scenes/walking_demo.tscn` instances `TerrainWorld`
  + an AnchorCameraRig; minimal consumer pattern
- **Deterministic outputs**: page content is deterministic (content-
  addressed); rendering is GPU-driven so frame-level pixel determinism
  is not promised

## Open questions

- **All implementation details** — primitive choice, module split,
  shader architecture, async streaming pattern, morph approach,
  visibility contract, debug overlay shape. ALL deferred to the
  Terrain Renderer PLAN doc, which is written after spec 15's
  research output exists.
- **Survey / HLOD support**: W4.1 had multi-shell quadtree for
  iso/topdown live views. W5's 3D-only runtime probably doesn't
  need this; but the bake-recipe Tier 3 system may. Defer.

## References

- W4.1 `ClipmapWorld.gd`, `ClipmapRing.gd`, `terrain_world_v3.gdshader`
  (~3900 + ~760 lines combined) — the system this spec replaces; W5
  starts fresh, doesn't copy
- `15_RENDERER_RESEARCH_BRIEF` (the gating doc)
- W4.1 retrospective lesson 1 ("ClipmapWorld is 3900 lines") — the
  warning this spec heeds

## Revision history

- 2026-05-16: initial skeleton draft (status BLOCKED pending research)
