# Plan: Terrain Renderer Implementation

> Spec: [21_TERRAIN_RENDERER.md](../specs/21_TERRAIN_RENDERER.md)
> Phase: 4 (terrain MVP, one biome)
> Created: 2026-05-17
> Status: in progress (Phase 4.1 deliverable)

Per spec 02 lifecycle: spec → **plan** → implement. This plan locks
build order + per-module file checklist + verification approach for
the terrain renderer. The spec says WHAT; this says HOW + WHEN.

## Reading order for the implementer

Before writing code, read in this order:
1. [21_TERRAIN_RENDERER.md](../specs/21_TERRAIN_RENDERER.md) — module
   decomposition + parameters + public API (the contract)
2. [15a_RENDERER_DECISION.md](../specs/15a_RENDERER_DECISION.md) —
   why clipmap; section D module-decomposition rationale
3. [20_TERRAIN_BACKEND.md](../specs/20_TERRAIN_BACKEND.md) — page
   contract this renderer consumes
4. [24_GROUND_VARIETY.md](../specs/24_GROUND_VARIETY.md) — variety
   architecture the material modules implement
5. [08a_GPU_CPU_CONTRACT.md](../specs/08a_GPU_CPU_CONTRACT.md) —
   thread-safety rules (RenderingDevice never from WorkerThreadPool)
6. [X_FRAME_BUDGET.md](../specs/X_FRAME_BUDGET.md) — terrain reserves
   2.0 ms at high tier; variety shader budget 1.0 ms

## Build order (the critical path)

```
┌─ 4.2 Backend ──────────────────────────────┐
│  TerrainPageRequest / TerrainPageResult    │
│  GpuTerrainBackend + compute shader        │
│  TerrainBackendAdapter (public)            │
└──────────────────┬─────────────────────────┘
                   │
┌─ 4.3 Kernel system ────────────────────────┐
│  Python NoiseStackKernel (reference)       │
│  GPU NoiseStackKernel (compute shader)     │
│  Cross-impl parity test                    │
└──────────────────┬─────────────────────────┘
                   │
┌─ 4.4 Renderer modules ─────────────────────┐
│  renderer/ first (geometry → ring → dispatch) │
│  streaming/ second (cache → residency → job) │
│  material/ third (slot mask → macro → pipeline) │
│  diagnostics/ last                          │
│  TerrainWorld composer wires everything    │
└──────────────────┬─────────────────────────┘
                   │
┌─ 4.5 Calibration sprint ───────────────────┐
│  Measure per-tier numbers; update          │
│  quality_tiers.json + X_FRAME_BUDGET       │
└──────────────────┬─────────────────────────┘
                   │
┌─ 4.6 Walking demo ─────────────────────────┐
│  One world bundle, one biome, walkable     │
│  60fps verified on RTX 5090 Laptop         │
│  (or extrapolated to 3060)                 │
└────────────────────────────────────────────┘
```

## Phase 4.2 — Backend (terrain pages)

**Goal**: a `TerrainBackend.request_page(req)` call returns a populated
`TerrainPageResult` whose GPU `Texture2DRD` height matches the Python
reference within tolerance.

| # | File | Purpose | Test |
|---|---|---|---|
| 1 | `engine/scripts/terrain/backend/TerrainPageRequest.gd` | RefCounted; request fields per spec 20 | `tests/unit/test_terrain_page_request.gd` (shape + capability validation) |
| 2 | `engine/scripts/terrain/backend/TerrainPageResult.gd` | RefCounted; result fields per spec 20 | `tests/unit/test_terrain_page_result.gd` (populated fields match request capabilities) |
| 3 | `engine/shaders/terrain_page_gen.glsl` | Compute shader: sample kernel → write Texture2DRD | exercised by `test_gpu_terrain_backend_real_device.gd` |
| 4 | `engine/scripts/terrain/backend/GpuTerrainBackend.gd` | Manages compute pipeline, dispatches per-request | `tests/unit/test_gpu_terrain_backend.gd` (mock kernel) + `tests/integration/test_gpu_terrain_backend_real_device.gd` (real GPU) |
| 5 | `engine/scripts/terrain/backend/TerrainBackendAdapter.gd` | Public facade; wraps GpuTerrainBackend via JobScheduler | `tests/integration/test_terrain_backend_adapter.gd` (request → result via Job; capability filtering) |
| 6 | `tests/integration/test_terrain_backend_parity.py` | Python NoiseStack vs GPU readback, tolerance ≤ 1e-3 | runs in `--full` (real GPU layer) |

**Spec 08a compliance gates**:
- All RenderingDevice calls inside `GpuJob` callbacks (never raw
  WorkerThreadPool tasks)
- All `Texture2DRD` + RID allocations registered with GpuResourceTracker
- All Job publishes `active_jobs` count to StreamingBudget
- Snapshot-keys-before-erase in any per-frame loops (pitfall meta-3)

**Verification**: `python -m world5.verify --full` includes the new
real-device test; parity test passes; integration test wires
backend ↔ JobScheduler ↔ StreamingBudget.

## Phase 4.3 — NoiseStack kernel config (NOT full kernel system)

**OA-C3 amendment 2026-05-17**: Phase 4.3 shipped NoiseStackKernel as
a config-only RefCounted wrapper, NOT the full kernel system spec 19
describes. The Kernel ABC + KernelComposer + polymorphic dispatch
land in the phase that introduces the second kernel (ErosionKernel,
pre-bake). GpuTerrainBackend currently hard-types `request.kernel:
NoiseStackKernel`; adding Erosion requires a backend refactor pass
+ a second GLSL pipeline branch + extending the cross-impl parity
harness. That refactor is in scope for whichever phase produces
ErosionKernel (likely Phase 5 alongside the texture pipeline, since
both are pre-bake operations).

**Goal of the work that DID ship**: same fBm function in Python +
GPU compute; readback matches within 1e-4 m tolerance.

| # | File | Purpose | Test |
|---|---|---|---|
| 1 | `pipeline/world5/kernels/__init__.py` | `Kernel` base class (sample(world_xz, seed) → array) | `tests/unit/test_kernel_base.py` |
| 2 | `pipeline/world5/kernels/noise_stack.py` | fBm impl (Python reference) | `tests/unit/test_noise_stack_python.py` (golden hash on known seeds) |
| 3 | `engine/scripts/terrain/kernels/NoiseStackKernel.gd` | GPU wrapper; emits compute dispatch params | `tests/unit/test_noise_stack_kernel.gd` |
| 4 | `engine/shaders/noise_stack.glsl` | Compute: fBm sampling matching Python | exercised by parity test |
| 5 | `tests/integration/test_noise_stack_parity.py` | Python ↔ GPU readback parity | `--full` |

**Deferred to Phase 4.5+** (per phase 4 checklist):
- `ErosionKernel` (pre-bake, not runtime; lives in pipeline)
- `DemFeatureKernel` (real-world heightmap features)

The kernel system V1 ships NoiseStack only. ErosionKernel is in scope
for Phase 5 (texture pipeline + pre-bake).

## Phase 4.4 — Renderer modules

**Goal**: a TerrainWorld instance in a demo scene renders the world
from camera; rings update + page-stream as camera moves; no hitches.

Build sub-order is **renderer → streaming → material → diagnostics →
composer** so each layer's tests can run before the next depends on it.

### 4.4.a — renderer/

| # | File | Purpose | Test |
|---|---|---|---|
| 1 | `engine/scripts/terrain/renderer/ClipmapGeometry.gd` | Cold-builds N ring meshes at startup; inner-hole cap math | `tests/unit/test_clipmap_geometry.gd` (mesh vertex count + bounds per ring) |
| 2 | `engine/scripts/terrain/renderer/ClipmapRing.gd` | One ring; set_center snap; LOD level + sample stride | `tests/unit/test_clipmap_ring.gd` (snap cell-alignment, bounds movement) |
| 3 | `engine/scripts/terrain/renderer/ClipmapDispatch.gd` | Per-frame snap + morph factor compute + uniform push | `tests/unit/test_clipmap_dispatch.gd` (computed morph values vs camera position) |

### 4.4.b — streaming/

| # | File | Purpose | Test |
|---|---|---|---|
| 4 | `engine/scripts/terrain/streaming/TerrainPageCache.gd` | LRU page cache; key = (ring_index, page_xz) | `tests/unit/test_terrain_page_cache.gd` (LRU eviction, hit/miss, budget bound) |
| 5 | `engine/scripts/terrain/streaming/ResidencyManager.gd` | Each frame diffs required vs resident; emits load/evict | `tests/unit/test_residency_manager.gd` (camera move → correct page set requested) |
| 6 | `engine/scripts/terrain/streaming/PageStreamingJob.gd` | GpuJob wrapping TerrainBackendAdapter.request_page | `tests/integration/test_page_streaming_job.gd` (full request-to-cache via Job) |

### 4.4.c — material/

| # | File | Purpose | Test |
|---|---|---|---|
| 7 | `engine/scripts/terrain/material/SurfaceSlotMask.gd` | Loads surface_slots.json → per-slot int indices | `tests/unit/test_surface_slot_mask.gd` |
| 8 | `engine/scripts/terrain/material/MacroAlbedo.gd` | Loads macro albedo texture; world-AABB sampling uniforms | `tests/unit/test_macro_albedo.gd` |
| 9 | `engine/scripts/terrain/material/MaterialPipeline.gd` | Per-ring ShaderMaterial; binds siblings + detail + macro + ring uniforms | `tests/unit/test_material_pipeline.gd` (uniform set inspection); `tests/integration/test_material_pipeline_real_device.gd` (real shader compile) |
| 10 | `engine/shaders/terrain_clipmap.gdshader` | Vertex: heightmap displacement + morph; fragment: variety_sample_3tap + detail + macro | exercised by integration test |
| 11 | `engine/shaders/variety_common.gdshaderinc` | Shared variety functions (sample_3tap, macro_albedo, world_noise) | exercised by terrain_clipmap.gdshader |

### 4.4.d — diagnostics/

| # | File | Purpose | Test |
|---|---|---|---|
| 12 | `engine/scripts/terrain/diagnostics/RingDebugOverlay.gd` | Toggleable wireframe per ring + bounds | `tests/unit/test_ring_debug_overlay.gd` (toggle on/off; visibility state) |
| 13 | `engine/scripts/terrain/diagnostics/PageDebugProbes.gd` | Query "what page covers world_xz", page age, evict reason | `tests/unit/test_page_debug_probes.gd` |

### 4.4.e — composer

| # | File | Purpose | Test |
|---|---|---|---|
| 14 | `engine/scripts/terrain/TerrainWorld.gd` | Composer; instantiates modules; wires signals; ≤ 800 lines | `tests/integration/test_terrain_world_smoke.gd` (instance + load bundle + frame tick); `tests/integration/test_terrain_world_walking.gd` (simulated camera move → pages stream) |
| 15 | `engine/scenes/components/terrain_world.tscn` | Scene component consumers instance | exercised by smoke test |

**Line-count gate** (verified by `tools/preflight/check_module_caps.py`,
extends doc_health pattern): TerrainWorld ≤ 800 lines; no other
terrain module > 1500 lines.

## Phase 4.5 — Calibration sprint

Per Phase 4 ROADMAP entry (SA-S2.1 fix):
- Measure every terrain-system frame budget on RTX 5090 Laptop (dev
  hardware), record extrapolation factor to RTX 3060/4060
- Update `engine/resources/quality_tiers.json` per-tier knobs:
  - `terrain.ring_count` (low: 4, medium: 5, high: 6, ultra: 7, cinematic: 8)
  - `terrain.ring_vertex_grid` (low: 128, medium: 192, high: 256, ultra: 384, cinematic: 512)
  - `terrain.page_size_samples` (low: 128, medium: 192, high: 256, ultra: 256, cinematic: 256)
  - `terrain.terrain_pages_max` (per tier)
  - `terrain.variety_layers` (low: 1 [siblings only], medium+: 1+3 [+ macro], high+: 1+2+3 [+ detail])
- Update `docs/specs/X_FRAME_BUDGET.md` per-system allocations with
  measured numbers

Multiple specs converge on this sprint (spec 10 streaming budget,
spec 13 quality tiers, spec 25 texture pipeline 90s estimate).

## Phase 4.6 — One-biome demo scene

| # | File | Purpose |
|---|---|---|
| 1 | `engine/worlds/walking_demo/biome_catalog.json` | One biome (e.g., temperate_grassland) |
| 2 | `engine/worlds/walking_demo/surface_slots.json` | Sibling textures per slot (4 siblings × ~5 slots) |
| 3 | `engine/worlds/walking_demo/materials/<biome>/<slot>/{albedo,normal,roughness,ao}.png` | Sibling PBR sets |
| 4 | `engine/worlds/walking_demo/macro_albedo.png` + `.json` | Macro albedo for the world |
| 5 | `engine/worlds/walking_demo/kernels/noise_stack.json` | Kernel params for the heightfield |
| 6 | `demo/scenes/walking_demo.tscn` | TerrainWorld + AnchorCameraRig + DirectionalLight3D + WorldEnvironment |
| 7 | `engine/tests/visual/test_walking_demo_capture.gd` | Capture-based perf test; runs in `--full` capture layer |

**Acceptance**:
- Walk the demo end-to-end without falling off / clipping into terrain
- 60fps p99 on dev hardware (RTX 5090 Laptop) measured over 60s walk
- Extrapolation to RTX 3060/4060 documented (rough 2-3× perf factor
  per Nvidia ratings; the 4.5 calibration produces the actual number)
- No visible texture repeat at close/mid distance (Layer 1 working);
  no obvious tiling at far distance (Layer 3 macro working)

## Subagent review schedule

Per [subagent_review_prompt.md](../workflows/subagent_review_prompt.md):

- **After 4.2 (backend)**: single subagent
  - SCOPE = `engine/scripts/terrain/backend/` + `engine/shaders/terrain_page_gen.glsl` + the tests, against spec 20 + spec 07 + spec 08a
  - LENSES = spec-vs-code adherence + cross-system integration (Job ↔
    StreamingBudget ↔ GpuResourceTracker) + pitfall recurrence (meta-2,
    meta-3)
  - ID_PREFIX = `TB-REV`

- **After 4.4 (renderer modules)**: 3 parallel subagents, all same SCOPE
  (`engine/scripts/terrain/renderer/` + `streaming/` + `material/` +
  `diagnostics/` + `TerrainWorld.gd`)
  - Agent 1: spec-vs-code adherence (does each module deliver what
    spec 21 promised? Line caps respected?) — ID_PREFIX `TR-SPEC`
  - Agent 2: performance claims + frame-budget arithmetic (against
    X_FRAME_BUDGET) — ID_PREFIX `TR-PERF`
  - Agent 3: cross-system integration (StreamingBudget +
    JobScheduler + AssetStream + ChangeBroadcast wires) — ID_PREFIX
    `TR-INTEG`

- **After 4.6 (demo close)**: single subagent
  - SCOPE = the full Tier 1 terrain vertical for forkability — could
    a consumer drop `engine/` into their project + author a world
    bundle?
  - LENSES = audit-fix verification (Phase 2 audit findings still
    intact?) + spec-vs-code (whole vertical) + test coverage gaps
  - ID_PREFIX = `T1-CLOSE`

Parent merges findings, applies criticals, defers minors.

## Open questions to lock during execution

Inherited from spec 21 + 24 open-questions sections:

| Question | Lock-by point |
|---|---|
| Texture2DRD vs Texture2DArrayRD for clipmap pages | end of 4.2 (backend) |
| Detail-array integration in Phase 4 vs Phase 5 | start of 4.4 material |
| Final ring_count at high tier | end of 4.5 (calibration) |
| Snap radius + morph band fraction (W4 values OK?) | end of 4.6 (demo) |
| Sibling count per slot (4 vs 6 vs 8) | end of 4.6 (demo, visual review) |

## Doc cap status

This file: ~270 lines (under 350 plan-doc cap).
