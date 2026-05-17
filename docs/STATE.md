# W5 State (Index)

> Current state of W5. Updated when systems ship / close / change
> contract. Per spec 05 doc architecture: this file is the index; per-tier
> details live in `state/*.md`.
>
> Last updated: 2026-05-17.

## One-sentence summary

**Phase 4 (terrain MVP) closed + Phase 4.7/4.8 standalone-run bugs
fixed + Phase 5 entry shipped.** Walking demo at
`demo/scenes/walking_demo.tscn` runs standalone on Godot 4.6.2
stable mono with real autoload bootstrap + local-RD page generation.
Renders the heightmap-displaced clipmap (5 rings @ high tier) but
shows a flat-brown fallback color band because there are no ground
textures yet — those land in Phase 5 once the in-flight texture
authoring completes. 5/5 verify layers green stable. Walking-demo
materials/ scaffold + sibling manifest schema ready for textures to
drop in.

## Per-tier state

- [state/state_meta.md](state/state_meta.md) — meta + Tier 0 cross-cutting
  systems (specs 00-18 + 08a + X_FRAME_BUDGET)
- [state/state_core.md](state/state_core.md) — Tier 1 core systems
  (specs 19-34)
- [state/state_world.md](state/state_world.md) — Tier 2 world systems
  (specs 35-41)
- [state/state_output.md](state/state_output.md) — Tier 3 output / packaging
  (specs 42-44)

## What exists right now

**Spec layer** (48 docs in `specs/`, all `draft`; 2 outside audits
+ 1 self-audit actioned across the Tier 0 + Phase 4 specs)
- AUDIT_FINDINGS.md / SELF_AUDIT_FINDINGS.md / SELF_AUDIT_PHASE_2_FINDINGS.md
- SYSTEM_INVENTORY.md + ORCHESTRATOR_PLANNING_GUIDE.md + REVIEW_BRIEF.md

**Tier 0 foundations** — all 13 systems in code with tests
- Log / World5 / QualityTiers / Job / JobScheduler / GpuJob /
  GpuResourceTracker / SpatialIndex / AssetStream / StreamingBudget /
  ChangeBroadcast / ContentAddress / WorldContract
- Autoloads registered at `/root/W5_<Name>` via project.godot +
  plugin.gd (W5_ prefix from Phase 4.7 to avoid class_name collision)
- W5Lookup helper for SUT lookups (test-override path + autoload
  fallback)

**Tier 1 terrain renderer (Phase 4 closed)** — clipmap-based, real-GPU
- Backend: GpuTerrainBackend uses local RD (Phase 4.8) + Python
  parity (1e-4 m tolerance, 7 cases including negative coords)
- NoiseStackKernel (Phase 4.3 — config wrapper; full kernel system
  with ABC/composer deferred until ErosionKernel lands)
- Renderer: ClipmapGeometry/Ring/Dispatch + TerrainPageCache +
  ResidencyManager + PageStreamingJob + MaterialPipeline +
  MacroAlbedo + SurfaceSlotMask + RingDebugOverlay + PageDebugProbes
- TerrainWorld composer (430 lines, under 800-line cap)
- Walking demo at `demo/scenes/walking_demo.tscn` runs standalone
  (post Phase 4.7+4.8 fixes) on Godot 4.6.2 stable mono
- Calibration measured: 4-6 ms CPU on RTX 5090 Laptop at 4-6 rings;
  F2 engaged conservatively for 3060 (per-tier ring_count 3/4/5/6/7)

**Tier 1 materials scaffold (Phase 5 entry)** — directory layout +
manifest schema ready for textures
- `engine/worlds/walking_demo/materials/biome_alpine/{ground,mid,
  rock}/`, plus `<slot>_variants/` for sibling sets, plus `detail/`
  for overlays — all gitkeeped, awaiting textures
- `material_variants.json` (W4-validated schema) + per-biome
  `detail_array.json` placeholder
- `MaterialVariants.gd` loader/validator + 8 unit tests

**Tools / build infrastructure**
- `python -m world5.verify` 4-mode CLI (fastest/fast/default/full);
  5 layers: pytest / gut (headless) / gut_real_gpu / preflight /
  capture. Currently 5/5 green stable.
- pytest 115 passed; gut ~250+ tests across unit/integration/perf/visual
- Godot 4.6.2 stable mono at `C:/Godot/v4.6.2/...` (pinned)
- Per-machine `demo/addons/world5/` junction → `../../engine/`

**Texture pipeline (Phase 5 — not started; plan exists)**
- Plan at `docs/plans/25_TEXTURE_PIPELINE_PLAN.md` (~370 lines,
  W4-validated 2026-05-17 staging test)
- User has textures being authored in parallel (offline)
- Phase 5.1 (module port from W4) + 5.4 (first biome) + 5.5 (shader
  Layers 1+2) pending

## What does NOT exist yet

- Real ground textures (Phase 5 deliverable; user authoring offline)
- Spec status sweep (48 specs still `draft`; Phase 5 close)
- Real RTX 3060 measurement (no hardware on dev rig; deferred)
- Decoration / foliage / atmosphere / water / weather / caves /
  deformation / persistence vertical code (Phases 6-14)

## What's blocked

Nothing. Phase 5 has its plan + scaffold; can start the W4 module
port anytime OR wait for the user's in-flight textures to land + run
the diversity batch directly. No system is dependency-blocked.

## Per-spec status snapshot

All 48 specs are `Status: draft`. Multiple outside-audit + self-audit
passes have reviewed the spec layer + driven amendments (notably
Phase 4 specs 21 + 24 + 25 + 23). The formal `draft → reviewed`
lifecycle sweep is still pending; planned for Phase 5 close (so
sweep runs against the most-evolved spec set).

## Recent activity (last 5 entries)

This is a CURRENT STATE index; the narrative log lives in build-notes.
Per spec 02 R7: STATE matches reality, not plans.

- 2026-05-17 (Phase 5 entry, `baa71ac`): spec amendments
  (23/24/25 absorbed the texture-pipeline workflow decisions); 
  walking_demo bundle scaffold (material_variants.json + per-slot
  dirs); MaterialVariants.gd loader + 8 tests. Awaiting textures.
- 2026-05-17 (Phase 4.8, `049ceb8`): GpuTerrainBackend uses local RD
  via `RenderingServer.create_local_rendering_device()`. Standalone
  scenes no longer error with "Only local devices can submit and sync".
- 2026-05-17 (Phase 4.7, `bc8c954`): autoload rename W5_ prefix +
  W5Lookup helper + project.godot `[autoload]` section. Walking demo
  now bootstraps autoloads in standalone runs without editor open.
- 2026-05-17 (Phase 4.6, `3f9b08c`): walking demo shipped — scene
  + WalkCamera + world bundle + stationary-camera baseline test.
  Phase 4 closes.
- 2026-05-17 (Phase 4.5, `b435640`): calibration sprint — first real
  perf measurement on RTX 5090 Laptop (4-6 ms at 4-6 rings;
  rasterization-bound). quality_tiers.json + X_FRAME_BUDGET.md
  updated. F2 trigger engaged for 3060.

## How to update this doc

When a system ships / closes / changes contract:
1. Update the appropriate `state/state_<tier>.md` file (per-system detail)
2. Update this file's "Recent activity" + "What exists" / "What does
   NOT exist" sections (one-line summary only)
3. Append a build-note to `build-notes/`

This file stays ≤ 200 lines. If it grows, content moves down into
per-tier files (per spec 05).
