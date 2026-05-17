# Spec: Terrain Renderer

> Status: draft (Phase 4 in progress)
> Tier: 1 (core)
> Depends on: 15a_RENDERER_DECISION (committed: clipmap), 20_TERRAIN_BACKEND, 22_BIOME_CATALOG, 23_MATERIALS_PBR, 24_GROUND_VARIETY, 30_ATMOSPHERE, 31_LIGHTING_GI
> Consumed by: every visible W5 scene

## Purpose

The runtime that displays a continuous, streamed heightfield world.
The largest visible system in W5. Consumes terrain backend pages,
biome catalog, material arrays, lighting recipes; produces the lit,
LOD'd, multi-biome 3D world the player walks through.

**Primitive**: clipmap (locked by spec 15a; 3 of 5 candidates eliminated
by Godot 4.5 capability survey; clipmap prototype measured at ~0.7
ms/frame on RTX 5090 Laptop). Multi-ring concentric grid centered on
camera; each ring covers 2× the area at ½ the sample density of the
prior ring; LOD-morph bands hide ring transitions.

W4.1's `ClipmapWorld.gd` was 3900 lines and a single god-file. W5
decomposes the renderer into multiple modules per audit recommendation;
no module exceeds 1500 lines, composer ≤ 800 lines.

## Non-goals

- 2.5D/topdown runtime view modes (Tier 3 bake recipes)
- Skybox / atmosphere rendering (delegated to atmosphere spec)
- Lighting beyond consuming the lighting recipe contract
- Decoration rendering (delegated to decoration runtime)
- Water / weather / cave rendering (Tier 2 systems with their own
  specs)
- Bake-time CPU "world preview" mode (handled by Tier 3 bake recipes
  spec, not this runtime)

## Module decomposition

```
engine/scripts/terrain/
├── renderer/
│   ├── ClipmapRing.gd            # one ring (mesh + bounds + LOD level)
│   ├── ClipmapGeometry.gd        # mesh-set generator (concentric grids + inner-hole cap)
│   └── ClipmapDispatch.gd        # per-frame ring update (snap, morph, draw)
├── streaming/
│   ├── TerrainPageCache.gd       # LRU page cache; key = (world_xz, LOD)
│   ├── ResidencyManager.gd       # what should be resident vs what is; emits load/evict
│   └── PageStreamingJob.gd       # Job-system wrapper around TerrainBackend.request_page
├── material/
│   ├── MaterialPipeline.gd       # per-ring shader + uniform setup
│   ├── SurfaceSlotMask.gd        # surface-slot → material-array index binding
│   └── MacroAlbedo.gd            # macro-tier far-field albedo (anti-repeat at distance)
├── diagnostics/
│   ├── RingDebugOverlay.gd       # ring-by-ring wireframe + bounds toggle
│   └── PageDebugProbes.gd        # which page covers world_xz, page age, evict reason
└── TerrainWorld.gd               # composer + public API (≤ 800 lines)
```

**Module responsibilities** (locked here; plan doc expands implementation):

- **ClipmapRing**: owns one MeshInstance3D + its world-space bounds.
  Knows its LOD level + sample stride. Exposes `set_center(world_xz)`
  for camera-snap.
- **ClipmapGeometry**: cold-builds the N ring meshes at startup. One-
  shot; never modifies geometry at runtime (only translates rings via
  set_center). Inner-hole cap is the trick that makes ring N+1 not
  z-fight with ring N inside.
- **ClipmapDispatch**: each frame, snaps each ring's center to its
  cell-aligned grid based on camera position; computes LOD-morph band
  factors; pushes uniforms.
- **TerrainPageCache**: keyed by `(ring_index, page_xz)`. Eviction
  policy: LRU bounded by `StreamingBudget.terrain_pages_max`.
- **ResidencyManager**: each frame, computes required page set from
  ring positions; diffs against resident set; enqueues
  PageStreamingJob for missing; emits evict for stale.
- **PageStreamingJob**: GpuJob that calls TerrainBackend
  (compute-shader sample) + uploads to cache slot. Publishes to
  StreamingBudget.
- **MaterialPipeline**: owns the per-ring ShaderMaterial; binds the
  per-biome material array + surface-slot mask + macro albedo + ring
  uniforms (level, morph_band, page tex array).
- **SurfaceSlotMask**: reads world bundle's surface_slots.json,
  produces the per-slot integer index used by the splat shader.
- **MacroAlbedo**: low-resolution world-spanning color texture sampled
  at far rings to break per-page repeat at distance (W4 trick that
  survives the audit).
- **RingDebugOverlay** + **PageDebugProbes**: built-in `--full` test
  layer + debug-key togglable in demo.
- **TerrainWorld**: composer only. Instantiates the modules, wires
  signals, owns the public API. Delegates everything. ≤ 800 lines.

## Public API

```gdscript
class_name TerrainWorld extends Node3D

@export var world_bundle_path: String         # "res://worlds/walking_demo/"
@export var camera_path: NodePath              # the camera to follow
@export var quality_tier_override: String = "" # default: QualityTiers current
@export var debug_overlay: bool = false        # toggle ring + page debug

signal world_loaded()
signal world_unloaded()
signal full_detail_ready()
signal page_loaded(ring_index: int, page_xz: Vector2)
signal page_unloaded(ring_index: int, page_xz: Vector2)

func is_full_detail_ready() -> bool
func get_resident_pages() -> Array              # [{ring: int, xz: Vector2, age_ms: int}, ...]
func sample_height_at(world_xz: Vector2) -> float
func get_debug_state() -> Dictionary            # ring centers, snap offsets, morph factors
```

Consumer instances `TerrainWorld`, points at a world bundle, gets a
streamed 3D world. Everything else is internal.

## Clipmap parameters (defaults; overridable per quality tier)

| Param | Default | Notes |
|---|---|---|
| ring_count | 6 | Per X_FRAME_BUDGET headroom on 3060/4060 — W4 used 8; verify in Phase 4 |
| ring_vertex_grid | 256 × 256 | Per ring; matches Phase 3 prototype |
| inner_cell_size_m | 0.5 | Ring 0 cell size; rings double per level |
| snap_radius_cells | 4 | Camera-to-near-ring snap radius (W4 value) |
| morph_band_fraction | 0.16 | Fraction of ring extent that morphs to next LOD |
| page_size_samples | 256 × 256 | Matches terrain backend page contract |
| terrain_pages_max | tier-dependent | Owned by StreamingBudget |

## Producer / consumer contract

- **Produces**: a 3D scene tree of rendered terrain; signals on
  lifecycle events; published streaming budget usage.
- **Consumes**: a world bundle (validated by world contract);
  terrain backend pages; lighting recipe; atmosphere profile;
  material arrays.

## Dependencies

- `15a_RENDERER_DECISION` (primitive: clipmap — committed)
- `20_TERRAIN_BACKEND` (page contract consumed)
- `22_BIOME_CATALOG` (per-biome material binding)
- `23_MATERIALS_PBR` (material array shape)
- `24_GROUND_VARIETY` (variety system integration; option C + B per 15a)
- `30_ATMOSPHERE` (sky, fog, haze)
- `31_LIGHTING_GI` (lighting recipe applied)
- `07_JOB_SYSTEM` + `08a_GPU_CPU_CONTRACT` + `09_ASYNC_ASSET_STREAMING`
  + `10_STREAMING_BUDGET` + `11_CHANGE_BROADCAST` (foundation primitives)

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

## Open questions (to lock during Phase 4 implementation)

- **Texture2DRD vs Texture2DArrayRD** for clipmap page storage (one
  slice per ring vs one texture per ring): measure both during 4.2
  backend build; commit before 4.4 renderer modules.
- **Final ring_count** at high tier: default 6; may rise to 8 if
  frame-budget arithmetic in 4.5 calibration shows headroom.
- **Camera-to-near-ring snap radius**: W4 used 4 cells; verify
  visual quality during 4.6 walking demo.
- **Morph band fraction**: W4 used 0.16; verify no visible LOD pop
  during 4.6.
- **Detail-array integration timing** (option B from spec 24): land
  alongside siblings (option C) in Phase 4 or defer to Phase 5
  (texture pipeline) so the array's content authoring can ride the
  pipeline build? Decide before 4.4 material modules ship.
- **Survey / HLOD support**: W4.1 had multi-shell quadtree for
  iso/topdown live views. W5's 3D-only runtime probably doesn't
  need this; but the bake-recipe Tier 3 system may. Defer to Tier 3.

## References

- W4.1 `ClipmapWorld.gd`, `ClipmapRing.gd`, `terrain_world_v3.gdshader`
  (~3900 + ~760 lines combined) — the system this spec replaces; W5
  starts fresh, doesn't copy
- `15_RENDERER_RESEARCH_BRIEF` (the gating doc)
- W4.1 retrospective lesson 1 ("ClipmapWorld is 3900 lines") — the
  warning this spec heeds

## Revision history

- 2026-05-16: initial skeleton draft (status BLOCKED pending research)
- 2026-05-17: unblocked by spec 15a (clipmap committed). Expanded
  module decomposition with per-module responsibilities; added
  clipmap-parameter defaults table; promoted "open questions" to
  Phase 4 lock-by dates; updated dependencies (15a not 15; added
  08a GPU/CPU contract).
