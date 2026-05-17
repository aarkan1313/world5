# Phase 4 — Terrain MVP (One Biome)

> Phase: Phase 4
> Status: 🚧 in progress
> Estimated sessions: 5-10
> Owner: agent + user joint; review subagents at sub-phase close
>
> Goal: production multi-ring clipmap renderer per spec 21 +
> material binding per spec 23 + ground variety per spec 24, one
> biome end-to-end, walkable demo scene in `demo/`. Validates the
> Tier 0 foundation + clipmap decision under real load.
>
> **Gates Phase 5** (texture pipeline), Phase 6 (second biome),
> and downstream verticals (decoration, foliage, atmosphere).

## Scope

Per spec 21 module decomposition (locked in spec 15a section D):

### Phase 4.1 — Unblock + spec finalize
- [ ] Update spec 21 TERRAIN_RENDERER: change Status from BLOCKED
      to draft; remove blocked-on-15 markers; expand sections that
      were deferred ("primitive choice", "module decomposition
      detail")
- [ ] Update spec 24 GROUND_VARIETY: change Status from BLOCKED to
      draft; commit to siblings + stochastic UV (option C) + detail
      array (option B) per 15a section D
- [ ] Update spec 23 MATERIALS_PBR: any clipmap-specific clarifications
- [ ] Write spec 21 plan doc at `docs/plans/21_TERRAIN_RENDERER_PLAN.md`
      with per-module build order + file checklist

### Phase 4.2 — Terrain backend implementation (spec 20)
- [ ] `engine/scripts/terrain/backend/TerrainPageRequest.gd` — request shape
- [ ] `engine/scripts/terrain/backend/TerrainPageResult.gd` — result shape
- [ ] `engine/scripts/terrain/backend/GpuTerrainBackend.gd` — main backend
- [ ] `engine/scripts/terrain/backend/TerrainBackendAdapter.gd` — public API
- [ ] Compute shader for kernel sampling → page output
      (`engine/shaders/terrain_page_gen.glsl`)
- [ ] Reuses spec 07 JobScheduler (GpuJob routing) + spec 12
      ContentAddress (page cache keys)
- [ ] gut tests for backend + cross-impl parity test against Python
      NoiseStackKernel (spec 19)

### Phase 4.3 — Kernel system in code (spec 19 partial)
- [ ] `pipeline/world5/kernels/__init__.py` — Kernel base class
- [ ] `pipeline/world5/kernels/noise_stack.py` — fBm impl (Python
      reference)
- [ ] `engine/scripts/terrain/kernels/NoiseStackKernel.gd` — GPU compute
      shader version
- [ ] Cross-impl parity test (Python ↔ GPU compute via readback)
- [ ] ErosionKernel + DemFeatureKernel deferred to Phase 4.5+
      (kernel system v1 ships NoiseStack only; erosion is pre-bake
      not runtime)

### Phase 4.4 — Renderer modules (spec 21 module decomposition)

Per spec 15a section D + spec 21 cap (composer ≤ 800 lines, modules
≤ 1500):

```
engine/scripts/terrain/
├── renderer/
│   ├── ClipmapRing.gd
│   ├── ClipmapGeometry.gd
│   └── ClipmapDispatch.gd
├── streaming/
│   ├── TerrainPageCache.gd
│   ├── ResidencyManager.gd
│   └── PageStreamingJob.gd
├── material/
│   ├── MaterialPipeline.gd
│   ├── SurfaceSlotMask.gd
│   └── MacroAlbedo.gd
├── diagnostics/
│   ├── RingDebugOverlay.gd
│   └── PageDebugProbes.gd
└── TerrainWorld.gd  (composer, ≤ 800 lines)
```

- [ ] Each module per spec 21 expanded sections
- [ ] gut tests per module
- [ ] Integration test: TerrainWorld + camera + walkable demo

### Phase 4.5 — Calibration sprint (after first walkable demo)
- [ ] Per Phase 4.5 ROADMAP entry (SA-S2.1 fix): measure every
      per-system frame budget + every tier knob on real RTX 3060
      hardware (or 5090-laptop with extrapolation documented)
- [ ] Update `engine/resources/quality_tiers.json` with measured
      values
- [ ] Update `docs/specs/X_FRAME_BUDGET.md` per-system allocations
- [ ] Multiple specs defer to this sprint (spec 10 streaming
      budget, spec 13 quality tiers, spec 25 texture pipeline 90s
      estimate)

### Phase 4.6 — One-biome demo scene
- [ ] `demo/scenes/walking_demo.tscn`: TerrainWorld + WalkCamera +
      lighting + sky
- [ ] First world bundle at `engine/worlds/walking_demo/`:
      biome_catalog.json (one biome), surface_slots.json,
      materials/, kernels/noise_stack.json
- [ ] Walk the world end-to-end, confirm 60fps + visual quality
- [ ] Capture-based test scene at `engine/tests/visual/`:
      verify --full unlocks the `capture` layer

## Review subagent dispatches

Per `docs/workflows/subagent_review_prompt.md`. Schedule:

- After Phase 4.2 (terrain backend): single subagent reviews
  backend impl vs spec 20 + spec 07 + spec 08a
- After Phase 4.4 (renderer modules): **3 parallel subagents**:
  - Lens 1: spec-vs-code adherence (does each module deliver what
    spec 21 promised?)
  - Lens 2: performance claims (frame budget arithmetic vs
    measured)
  - Lens 3: cross-system integration (StreamingBudget +
    JobScheduler + AssetStream wires)
- After Phase 4.6 (demo close): single subagent reviews the full
  Tier 1 vertical for forkability (could a consumer drop this in?)

## Pillar verification at close

Phase 4 close requires:
- ✅ Pillar 1: visual quality — terrain reads as "AAA-tier
  open-world" at close + mid + far distances; macro_albedo working;
  no obvious texture repeat (single-biome version; spec 24 ships
  siblings architecture; full anti-repeat polish at Phase 7)
- ✅ Pillar 2: performance — walkable demo at 60fps p99 on RTX
  3060 (or extrapolated from RTX 5090 Laptop); per-system frame
  costs measured against X_FRAME_BUDGET
- ✅ Pillar 3: architecture — no god-files (TerrainWorld ≤ 800
  lines verified); modules ≤ 1500 verified; preflight passes
- ✅ Pillar 4: time — no shortcuts taken; calibration sprint
  ran; spec contracts honored

## Out of scope (defer to later phases)

- Foliage (Phase 8) — terrain only; no trees yet
- Decoration (Phase 7) — terrain only; no rocks/props yet
- Atmosphere (Phase 9) — basic sky + dir light only; no Bruneton
- Multiple biomes (Phase 6) — one biome; second proves biome-to-
  biome architecture
- Water (Phase 10), weather (11), caves (12), etc.

## Open questions to lock during Phase 4

- [ ] Texture2DRD vs Texture2DArrayRD for clipmap pages (one slice
      per ring) — measure both; pick winner
- [ ] Ring count default (W4 had 8 rings; clipmap perf scales
      ~linearly; default may be 6 at high tier per X_FRAME_BUDGET
      headroom)
- [ ] Camera-to-near-ring snap radius (W4 used 4 cells; verify)
- [ ] LOD-morph band fraction (W4 used 0.16; verify visual quality
      at production density)
- [ ] Detail-array integration timing (option B alongside C, or
      sibling-only first?)

## Phase 4 close criteria

- [ ] Spec 21 + 24 updated (no more BLOCKED status)
- [ ] All Phase 4.x sub-phases shipped with tests
- [ ] `verify --full` passes (now exercising capture layer too)
- [ ] Walking demo runs in `demo/`; one biome end-to-end
- [ ] 60fps p99 verified (RTX 3060 directly OR 5090-laptop +
      extrapolation documented)
- [ ] Subagent reviews dispatched + findings actioned
- [ ] Build-note + STATE + ROADMAP updates pushed

## Estimated session count

| Sub-phase | Est sessions |
|---|---|
| 4.1 spec unblock + plan doc | 0.5 |
| 4.2 terrain backend | 1-2 |
| 4.3 kernel system | 1 |
| 4.4 renderer modules | 2-3 |
| 4.5 calibration sprint | 1 |
| 4.6 one-biome demo | 1-2 |
| Review subagent rounds (3 dispatches) | 0.5 |
| Phase 4 close | 0.3 |
| **Total** | **5-10** |

## Doc cap status

This file: ~170 lines (under 350 cap).
