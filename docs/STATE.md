# W5 State (Index)

> Current state of W5. Updated when systems ship / close / change
> contract. Per spec 05 doc architecture: this file is the index; per-tier
> details live in `state/*.md`.
>
> Last updated: 2026-05-17.

## One-sentence summary

**Phase 5.1 W4 module port is the active sub-phase.** Phase 4.9 closed
end-to-end last session (audit C1 + C2 + S8 fixed — multi-page
heightmap binding + per-fragment slot selection + biome_catalog).
Remaining audit items all converge on one unlock: port
`D:/assets/world 4/pipeline/textures/tx_*.py` (11 modules) +
`D:/assets/world 4/pipeline/diversity_*.py` + `build_contact_sheet.py`
(4 drivers) into `pipeline/world5/textures/` so the W5 pipeline runs
end-to-end without depending on `D:/tmp/w5_candidates/`. W4 source
is stable (5 trivial line diffs in working tree). Plan: file-copy +
path-edit per [plan 25 §5.1](plans/25_TEXTURE_PIPELINE_PLAN.md);
~1-2 sessions. Verify still 5/5 layers green stable at 139 pytest +
gut + gut_real_gpu + preflight + capture.

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

**Tier 1 terrain renderer (Phase 4 shipped with critical gaps)** — clipmap-based, real-GPU
- Backend: GpuTerrainBackend uses local RD (Phase 4.8) + Python
  parity (1e-4 m tolerance, 7 cases including negative coords)
- NoiseStackKernel (Phase 4.3) — config wrapper only. **Spec 19 v1
  also requires ErosionKernel + DemFeatureKernel + KernelComposer;
  scheduled for Phase 5.7 erosion sprint** (was unscheduled pre-audit)
- Renderer: ClipmapGeometry/Ring/Dispatch + TerrainPageCache +
  ResidencyManager + PageStreamingJob + MaterialPipeline +
  MacroAlbedo + SurfaceSlotMask + RingDebugOverlay + PageDebugProbes
- TerrainWorld composer (514 lines, under 800-line cap)
- Walking demo at `demo/scenes/walking_demo.tscn` runs standalone
  (post Phase 4.7+4.8 fixes) on Godot 4.6.2 stable mono; renders
  displaced firn-snow alpine post Phase 5.4
- Calibration measured: 4-6 ms CPU on RTX 5090 Laptop at 4-6 rings.
  **Spec 21 perf bar NOT met on 3060** — extrapolation gives 13-17
  ms at 4 rings (7-12× over 2.0 ms budget). F2 fallback decision
  TBD pending real hardware. ROADMAP currently claims "F2 engaged
  conservatively"; correct claim is "viability unproven"
- **Phase 4.9 audit-closure fixes (shipped 2026-05-17)**:
  - C1 ✅: RingHeightArray + bind_height_array() + per-fragment
    page lookup in vertex shader. Outer rings now bind a
    Texture2DArray of all resident pages; shader picks correct
    layer per fragment via world XZ → page coord. Chunk seams
    eliminated
  - C2 ✅: BiomeCatalog + bind_all_slots() + w5_slot_weight() +
    fragment loop over slot_count. Mid + rock textures now reach
    the GPU on slopes + cliffs that match their catalog selectors
  - C3 ⏸: sibling_blend_freq tune deferred to Phase 5.6 (needs
    eye-height walking with real textures to calibrate)

**Tier 1 materials scaffold (Phase 5 entry)** — directory layout +
manifest schema ready for textures
- `engine/worlds/walking_demo/materials/biome_alpine/{ground,mid,
  rock}/`, plus `<slot>_variants/` for sibling sets, plus `detail/`
  for overlays — all gitkeeped, awaiting textures
- `material_variants.json` (W4-validated schema) + per-biome
  `detail_array.json` placeholder
- `MaterialVariants.gd` loader/validator + 8 unit tests

**Tier 1 variety shader (Phase 5.5)** — Layer 1 + Layer 2 fully wired
end-to-end (shader + manifest loaders + Texture2DArray builders +
authoring tool + preflight)
- `variety_common.gdshaderinc`: `w5_variety_sample_3tap()` (Heitz-
  Neyret simplified 3-tap stochastic UV blend) + `w5_detail_blend()`
  (2-tap overlay blend) primitives
- `terrain_clipmap.gdshader`: optional Layer 1 + Layer 2 paths gated
  by `has_siblings` + `has_detail` flags; unbound flag defaults
  preserve the pre-5.5 macro-only render so the demo works today
- `MaterialPipeline.bind_sibling_array()` + `bind_detail_array()` —
  binders for the shader; ready to flip on the moment textures land
- `MaterialVariants.gd` + `DetailArray.gd` — manifest loaders +
  validators (spec 24 schemas)
- `SiblingTextureArray.gd` + `DetailTextureArray.gd` — runtime
  loaders that assemble a `Texture2DArray` from a manifest +
  on-disk PBR images; biome-relative `source` resolution
- `pipeline/world5/textures/promote.py` — net-new CLI tool
  (W4 had this as manual file moves); copies candidate textures
  into a world bundle + atomically updates `material_variants.json`
- `world_contract/materials_manifests.py` — preflight check that
  validates manifests against on-disk files; distinguishes "not
  promoted yet" (warning) from "broken promote state" (error)
- 45+ tests covering all of the above (24 new Python + 19 new GDScript
  + 4 real-GPU integration)

**Tools / build infrastructure**
- `python -m world5.verify` 4-mode CLI (fastest/fast/default/full);
  5 layers: pytest / gut (headless) / gut_real_gpu / preflight /
  capture. Currently 5/5 green stable.
- pytest 115 passed; gut ~250+ tests across unit/integration/perf/visual
- Godot 4.6.2 stable mono at `C:/Godot/v4.6.2/...` (pinned)
- Per-machine `demo/addons/world5/` junction → `../../engine/`

**Texture pipeline (Phase 5 — partially shipped; gaps documented)**
- Plan at `docs/plans/25_TEXTURE_PIPELINE_PLAN.md` (~370 lines,
  W4-validated 2026-05-17 staging test)
- Phase 5.4 (alpine first-biome): textures promoted (BFL 2048² +
  local 1024²). ground + 3 siblings × 3 slots = 48 files. But only
  the ground slot renders today (C2 blocks mid/rock); no
  macro_albedo (S2); no detail overlays (S3)
- Phase 5.5 (shader Layer 1+2): primitives + binders + Texture2DArray
  loaders + TerrainWorld wire-up shipped. Single-active-slot only
  (C2). sibling_blend_freq=0.10 produces visible repeat (C3)
- Phase 5.1 (W4 module port): HELD. Only promote.py exists in
  pipeline/world5/textures/. The texture team's external chain at
  d:/tmp/ is stable; unblock 5.1 next
- Phase 5.4.b (detail overlays + sibling tune) + 5.6 (real calibration)
  + 5.7 (erosion sprint) pending after 4.9 + 5.1

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

- 2026-05-17 (Phase 5.1 opening — W4 module port active):
  Phase 5.1 sub-phase opened. Plan = port 11 W4 tx_*.py modules +
  4 drivers (diversity, contact_sheet, review, material_variants)
  into pipeline/world5/textures/. Unblocks 4.9.c macro_albedo +
  5.4.b detail overlays + 5.6 calibration + audit S5/S6/S7. W4
  source confirmed stable (5 trivial diffs in working tree).
- 2026-05-17 (Phase 4.9 closed — audit C1+C2+S8 fixed):
  RingHeightArray multi-page heightmap binding (C1, 4.9.a) +
  per-fragment slot selection with BiomeCatalog selectors (C2, 4.9.b)
  + walking_demo biome_catalog.json (S8, 4.9.d). 3 critical audit
  bugs closed; 27 new tests (3 real-GPU visual regressions). Phase 4
  + 4.6 + 5.5 status moved from ⚠️ to ✅ in ROADMAP. Walking demo
  capture shows continuous displacement across the visible distance
  + slot textures lighting the mid/rock bands on slopes. Build notes
  at phase_4_9_close + phase_4_9_a + phase_4_9_b_d.
- 2026-05-17 (Phase 5.4 first-biome shipped + brown-band bug fix):
  texture team delivered 91 candidates across 16 (biome, slot) pairs
  at D:/tmp/w5_candidates/ (BFL flux-2-pro 2048² + local NVFP4 1024²).
  promote.py ran for alpine ground/mid/rock with base + 3 siblings
  each → 48 files into world bundle + manifest updated. Capture
  initially still showed flat-brown band; two outside audits found
  THREE compounding bugs all silently masking each other: (a) Godot
  4.6 ignores ArrayMesh.custom_aabb so rings frustum-culled the
  moment vertex shader displaced verts off y=0; (b) ClipmapGeometry
  generated triangles without normals; (c) winding was back-facing
  from above. Fixes in ClipmapRing.configure (set MeshInstance3D
  .custom_aabb) + ClipmapGeometry (add normals + flip winding) +
  cast_shadow=OFF on rings. Walking demo now renders gorgeous
  displaced firn-snow alpine terrain. 2 new mesh-level regression
  guards in test_terrain_capture_baseline_real_device.gd catch the
  bug class without needing SubViewport pixel capture. Textures
  themselves are gitignored (author-supplied, per-machine, 297 MB).
- 2026-05-17 (Phase 5.5 TerrainWorld wire-up):
  TerrainWorld._load_world_bundle now calls MaterialVariants +
  DetailArray loaders, assembles Texture2DArrays via
  SiblingTextureArray + DetailTextureArray, binds them on every
  ring shader material. End-to-end pipeline complete: when textures
  land + promote.py runs + walking_demo starts → terrain auto-renders
  with Layer 1+2 active, no further code edits. 4 integration tests
  added covering bound, unbound, and missing-manifest paths.
- 2026-05-17 (Phase 5.5 runtime glue + promote tool):
  DetailArray + SiblingTextureArray + DetailTextureArray loaders
  (manifest → Texture2DArray). promote.py CLI (net-new W5 tool;
  workflow-critical). World-contract `materials_manifests` preflight
  with warning/error split (not-promoted-yet vs broken-promote).
  +24 Python tests, +19 GDScript tests; 139 pytest + gut all green.
- 2026-05-17 (Phase 5.5 shader work): Spec 24 Layer 1
  (siblings + 3-tap stochastic UV) + Layer 2 (detail overlays)
  shader primitives + MaterialPipeline binders shipped. 22 new tests
  green. Walking demo unchanged visually because no sibling/detail
  textures bound yet; once Phase 5.4 promotion runs, binders flip on
  without further shader work.
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

## How to update this doc

When a system ships / closes / changes contract:
1. Update the appropriate `state/state_<tier>.md` file (per-system detail)
2. Update this file's "Recent activity" + "What exists" / "What does
   NOT exist" sections (one-line summary only)
3. Append a build-note to `build-notes/`

This file stays ≤ 200 lines. If it grows, content moves down into
per-tier files (per spec 05).
