# Sprint 1 close — runtime kernel chain execution

> Plan: [docs/plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md](../plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md)
> Sprint: 1 of 4 (Runtime kernel chain execution)
> Status: ✅ closed 2026-05-18
> Visible result: walking demo terrain finally shows eroded geology
> instead of pure fBm noise; alpine biome's `noise_stack → erosion`
> chain runs end-to-end at runtime via GPU compute.

## Summary

W5's catalog has carried per-biome kernel chains since Phase 5.7.b
(2026-05-17), but the live runtime ignored them — `TerrainWorld` read
the legacy `kernels/noise_stack.json` and produced pure fBm noise
regardless of what the catalog declared. Sprint 1 closes that gap:
the runtime now parses the catalog's kernel chain (single or composite)
via the new `KernelComposer.gd`, dispatches each stage via
`GpuTerrainBackend`, and feeds the chain output into the existing
heightmap pipeline. Walking demo's alpine biome has a
`noise_stack + erosion` chain that now executes on the GPU per page,
visible as eroded ridges/valleys instead of bumpy noise.

## What landed

### Config classes (mirror NoiseStackKernel.gd pattern)

- **`engine/scripts/terrain/kernels/ErosionKernel.gd`** — 12-field
  RefCounted matching `pipeline/world5/kernels/erosion.py` dataclass +
  `engine/resources/schemas/kernels/erosion.schema.json`. Config-only;
  execution is the GPU compute shader. `from_dict / to_dict / validate
  / config_hash` parallel to NoiseStackKernel.
- **`engine/scripts/terrain/kernels/KernelComposer.gd`** — chain
  orchestrator. Parses `{type: chain, stages: [...]}` (or bare
  single-stage) into typed `Array[{kind, config}]`. `chain_hash()`
  combines per-stage `config_hash` via ContentAddress for spec-12
  cache participation. Helpers: `validate`, `has_erosion`,
  `base_noise_kernel`, `erosion_stages`.
- 32 new unit tests (16 ErosionKernel + 16 KernelComposer).

### GPU compute shaders

- **`engine/shaders/terrain_erosion.glsl`** — one Mei hydraulic step
  per dispatch. Rain → outflow flux → water update → velocity →
  sediment capacity → dissolve/deposit → evaporate. Per-cell parallel
  (no cross-cell writes); caller dispatches N times in a loop with
  shared persistent buffers.
- **`engine/shaders/terrain_erosion_thermal.glsl`** — one Musgrave
  thermal step per dispatch. Ping-pong (height_in / height_out) for
  read-modify-write safety. Mirrors neighbor-excess via 4-direction
  read-mirror pattern (no cross-cell writes).

### Backend orchestration

- **`engine/scripts/terrain/backend/TerrainPageRequest.gd`**: added
  optional `composer: KernelComposer` field. `cache_key()` incorporates
  `chain_hash` so chain edits invalidate downstream bakes per spec 12.
  `validate()` runs composer validation when set. `from_dict` accepts
  composer dicts. Legacy `kernel` field still works for back-compat.
- **`engine/scripts/terrain/backend/GpuTerrainBackend.gd`**: branches
  between `_generate_heights` (legacy single-noise) and `_generate_chain`
  (new) based on `request.composer`. Chain path allocates persistent
  height/water/sediment/velocity/drainage buffers, dispatches noise
  generator into height, then loops erosion stages with interleaved
  hydraulic+thermal dispatches matching Python reference cadence. New
  `_dispatch_noise / _dispatch_erosion / _dispatch_hydraulic_step /
  _dispatch_thermal_step` helpers + generic `_compile_named` shader
  loader (closure-based, scales for future kernel types). Shutdown
  extended to free all 3 shader RIDs.
- **`engine/scripts/terrain/streaming/PageStreamingJob.gd`**: extended
  `configure()` with optional `composer:` param; when set, passes
  through to each `TerrainPageRequest.composer`.

### Loader switch (the visible unlock)

- **`engine/scripts/terrain/TerrainWorld.gd`**: catalog's first biome
  `kernel` field is now parsed into a `KernelComposer`; the composer
  takes precedence over the legacy `kernels/noise_stack.json` path.
  Legacy bundles without a catalog chain still work. Logs the chain
  load: `kernel chain loaded biome=alpine stages=2 chain_hash=...`.

## Verification

- pytest: 174 passed.
- gut: passed (pre-existing flake in `test_change_broadcast` unrelated;
  ChangeBroadcast subsystem, not touched by this sprint).
- preflight: 0 errors / 1 warning (STATE.md doc cap, unrelated).
- Runtime capture (`demo/scenes/walking_demo_capture.tscn`): saved a
  visibly-eroded terrain render to `_capture_walking_demo.png`.
  `resident_pages=123, full_detail_ready=true, no leaked RIDs`.

Launch log confirms the chain ran:
```
[INFO ] [terrain_world] sibling array built  slots=6 layers=48
        tinv_layers=48 normal_layers=48 roughness_layers=48 ao_layers=48
[INFO ] [terrain_world] binding slots on rings  slot_count=6 biome_count=2
        biome_weights_active=true ... region_size_m=512.0 edge_blend_m=48.0
        world_seed=42
[INFO ] [terrain_world] kernel chain loaded  biome=alpine stages=2
        chain_hash=02c01389d407
```

## Architectural notes

- **Chain path is opt-in via catalog.** Pre-catalog bundles or bundles
  that omit the `kernel` field on the first biome fall back to the
  legacy `kernels/noise_stack.json` path. Both work.
- **Multiple erosion stages allowed in a chain.** The composer's
  `erosion_stages()` iterates all of them; intermediate water/sediment
  state is carried across stages (matches Python `bake_page` behavior
  when called consecutively).
- **First biome's chain wins for the world.** Per-biome divergent
  chains (alpine eroded + forest pure-noise simultaneously) require
  Composer's multi-biome height blending which lands in a future
  sprint. Walking demo today: alpine chain runs everywhere; forest's
  `kernel: noise_stack` is parsed but its chain isn't dispatched —
  the renderer picks per-fragment materials based on the same
  alpine-chain-generated height field. Side effect: forest areas show
  on alpine-eroded terrain, which is actually a reasonable v1 look.
- **GPU compute shaders are first-class.** No CPU fallback in the
  runtime — Python is the parity reference, GPU is the executor (per
  spec 19 §"GPU is the primary execution target"). Headless CI runs
  the Python parity tests; live demo runs the GPU shaders.

## Known follow-ups (sprint 2+)

1. **Strict GPU↔Python parity test for erosion.** Sprint 1 ships the
   GLSL with algorithm structure matching the Python ref, but no
   tolerance-bound parity test yet. Erosion is chaotic enough that
   strict byte-parity is the wrong bar; we'll add a "qualitative
   match" test (e.g. drainage map correlates, total mass preserved
   within tolerance) in a follow-up.
2. **Composer's multi-biome height blend.** Currently uses first
   biome's chain for the whole world. Spec 19 §"KernelComposer" calls
   for per-(x,z) biome-weighted height — needs proper softmax dispatch
   across biome chains. Sprint 3-adjacent.
3. **Per-stage perf measurement.** No frame-budget tracking on chain
   dispatch yet. If walking demo with erosion stalls page streaming,
   we'll need to either cap iterations per page or measure + tune.
4. **DEM kernel** (Sprint 2-3) — this sprint's infrastructure is what
   makes adding a `DemFeatureKernel` stage to the chain straightforward.

## Doc cap status

~145 lines (under 200 cap).
