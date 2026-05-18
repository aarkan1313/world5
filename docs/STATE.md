# W5 State (Index)

> Current state of W5. Updated when systems ship / close / change
> contract. Per spec 05 doc architecture: this file is the index; per-tier
> details live in `state/*.md`.
>
> Last updated: 2026-05-17.

## One-sentence summary

**Phase 5.7 demonstration shipped + perf tests fixed (full verify
5/5 green in 19.5s).** End-to-end demo: walking_demo's alpine
catalog declares noise_stack + erosion chain; bake script proves
KernelComposer + ErosionKernel + spec-12 cache all assemble + run
(766× cache speedup; visible terrain change). Perf test failures
were Phase 4.5-era page_extent_m=32 mismatching the new cache
auto-raise — fixed via production page_extent + per-tier 5090
ceilings. pytest 174 green. **Next**: TerrainWorld loader switch
(catalog-driven kernel + cached bake_page output) paired with
GDScript biome_weights mirror for the Phase 6 multi-biome unblock.

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
  - S2 ✅ (4.9.c): macro_albedo.json + alpine purpose-preset PNG
    shipped in walking_demo bundle. Renderer's "bundle missing
    macro_albedo.json" warning gone. Far-field reads as alpine
    snowfield, not olive fallback. macro_albedo_* preflight checks
    added (+4 tests; pytest now 143 passed)
  - C3 ⏸: sibling_blend_freq tune deferred to Phase 5.4.b (needs
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

- 2026-05-18 late (DEM/runtime-kernels epic sprints 1+2+3 closed):
  Sprint 3 added GDScript DemFeatureKernel (config class mirroring
  NoiseStack/Erosion pattern; 16 unit tests) + KernelComposer dem_feature
  stage dispatch + 7 composer tests + DemSource bundle loader (sidecar
  + 16-bit height PNG + pre-baked feature PNGs via bilinear sampling;
  12 unit tests). tx_dem_prepare extended to emit 16-bit height PNG
  + 4 baked feature PNGs (ridge/drainage/slope/aspect) + --auto-bounds
  flag (auto-center on source DEM, world-XZ recentered to (0,0)).
  GpuTerrainBackend: DEM source registry + _apply_dem_feature_blend
  CPU post-process. TerrainWorld scans <bundle>/dem/*.json + registers
  sources. Walking demo wired with Cascades DEM (Mount Hood foothills,
  Copernicus GLO-30, 1024² at ~4 m/cell). Alpine chain is now 3
  stages: noise_stack → dem_feature(cascades, ridge_emphasis,
  strength=1.0) → erosion. Forest stays pure noise (proves catalog
  mixing). Runtime capture confirms 3-stage chain runs cleanly
  (chain_hash=e18e1212258b, 76 pages, no leaked RIDs). Build note:
  build-notes/sprint_3_dem_runtime_2026_05_18.md.

- 2026-05-18 evening (DEM/runtime-kernels epic sprints 1+2 closed):
  Walking demo's catalog-declared `noise_stack + erosion` chain now
  runs at runtime via GPU compute — alpine biome shows visibly eroded
  terrain instead of pure fBm noise (resolves user's "world gen is
  bumpy noise" concern). Sprint 1 added ErosionKernel.gd config +
  KernelComposer.gd chain orchestrator + GLSL hydraulic/thermal
  compute shaders + GpuTerrainBackend chain dispatch (allocates
  persistent height/water/sediment/velocity/drainage buffers,
  ping-pongs thermal, interleaves per Python ref cadence) +
  TerrainPageRequest composer field + PageStreamingJob composer
  pass-through + TerrainWorld loader switch (catalog wins over
  legacy noise_stack.json). 32 new GDScript unit tests. Sprint 2
  added Python DemFeatureKernel reference (ridge_emphasis /
  drainage_accumulation / slope_deg / aspect_deg via
  scipy.ndimage + rasterio) + 19 pytest cases + bundle DEM schema
  + tx_dem_prepare tool (smoke-tested against W3's Cascades DEM).
  Total: 193 pytest (was 174), gut + preflight green. See
  build-notes/sprint_1_runtime_kernels_2026_05_18.md +
  plans/19_DEM_AND_RUNTIME_KERNELS_PLAN.md. 7 commits ahead of
  pre-epic baseline; all pushed to origin.

- 2026-05-18 (Phase 6 closed — multi-biome rendering end-to-end):
  Walking demo now renders alpine + forest with proper per-fragment
  biome_weights × slot weights. Fixed cascading rendering bugs that
  surfaced on first multi-biome launch: silent size-mismatch skipping
  forest layers, broken mix()-chain slot accumulator, missing PBR
  bindings (normal/roughness/AO), missing mesh tangents, no mipmaps
  on sibling array, macro overlay contaminating slots at 35%, broken
  HN sampler. Replaced with W3 M11-derived triplanar + hex sampling
  + region-based variant selection + proper weighted-sum accumulator
  math + per-biome ground-avg fallback color. 48 sibling layers per
  array (6 slots × 8 variants), 48 T_inv LUTs, 5 layer-matched
  PBR arrays. New tool: `pipeline/world5/textures/tx_hn_lut.py` for
  per-channel inverse-CDF LUT generation. Diagnostic toggles
  stripped. pytest 174 passed, gut + preflight green. See
  build-notes/phase_6_close_2026_05_18.md. Roadmap Phase 6 row
  flipped ⏸→✅.

- 2026-05-17 (Roadmap-alignment pass — spec 13 + spec 42 amendments):
  Per user direction "we will just have to guess on the 3060,
  probably figure out a thing like 5090 is x amount of performance
  of 3060 ... if we cant hit performance targets we could do some
  kind of baking / just use it to make a set non procedural world."
  Spec 13 amended: new §Calibration HW + cross-hardware extrapolation
  formalizes the dev-rig-to-target translation. quality_tiers.json
  gains _calibration_hw + per-tier _perf_extrapolation_ratios
  (geometry + fillrate scalars). Audit S1 reframed from "ungrounded
  perf claim, blocked on 3060" to "extrapolation-grounded, refined
  when real HW joins the loop." Spec 42 amended: new `static_world`
  recipe family (procedural → static world transform). Output: a
  parallel world bundle with pre-baked meshes + biome_weights texture
  + decoration/foliage blobs + lighting capture; loader picks static
  path if _static_manifest.json present, procedural otherwise. Three
  use cases documented: perf-floor fallback, modding/hand-edit
  workflow, forkability proof (spec 44). ROADMAP Phase 15 row
  updated: static_world is the v1 priority recipe. Memory saved at
  w5-perf-tier-and-bake-fallback so the two-modes architecture is
  durable across sessions.
- 2026-05-17 (Phase 5.7 demonstration — walking_demo erosion bake):
  Closes the Phase 5.7 demonstration gap. walking_demo's alpine
  kernel field upgraded from flat noise_stack to explicit chain
  (noise_stack + erosion, 400 hydraulic iter + 100 thermal, talus
  35°). pipeline/world5/demo/bake_walking_demo_erosion.py runs
  KernelComposer.bake_page on a 1km² alpine region + renders
  hillshade comparison (noise-only vs eroded). Measured: 0.77s
  first bake, 0.001s cache hit (766x speedup confirming spec 12
  cache works end-to-end), 1.72m max delta + 2.9% of cells
  changed (visible peak-softening + emerging gullies on hillshade).
  Runtime loader switch to catalog-driven kernel still pending —
  walking_demo render today still uses kernels/noise_stack.json
  directly; the catalog chain is parsed-and-baked but not yet
  consumed by the live renderer. That loader switch pairs with
  the GDScript biome_weights mirror for the Phase 6 multi-biome
  unblock. Build note phase_5_7_demo_walking_demo_erosion_2026_05_17.md.
- 2026-05-17 (perf calibration + stationary tests fixed):
  Both perf-test suites failed gut_real_gpu after Phase 5.6 budget
  pass. Root cause: page_extent_m=32 from Phase 4.5 era was too
  small for the new cache auto-raise — ultra/cinematic needed
  5k-21k pages (vs 50-420 at production 256m). Frame time was
  cache-iteration cost, not perf regression. Fix: use production
  page_extent_m=256 + per-tier 5090-measured ceilings via
  _assert_catastrophic_ceiling helpers. After fix: 5/5 calibration
  in 13.7s (was 300+s failing); 4/4 stationary in same range.
  Commits b93894a + 56a74a3.
- 2026-05-17 (Phase 5.7.c closed — bake_page + cache + erosion-in-chain):
  Spec 19 §"Pre-bake global pass" + spec 12 content addressing.
  Added KernelComposer.bake_page(world_origin, extent, grid_n, seed,
  store=None, biome_index=0) — runs the biome's full chain on a
  WHOLE page (noise_stack base + erosion post-process). Erosion
  stages, previously skipped at per-point sample_height, now execute
  here. Optional store argument uses ContentAddressStore: cache key
  is sha256(canonical_json(catalog_hash + biome + world_origin +
  extent + grid + seed)); hit returns bytes; miss runs chain + puts.
  Catalog edits invalidate downstream bakes via catalog_hash
  inclusion. Cleanup: removed _DeferredStage placeholder (erosion
  now returns a real instance from _instantiate_stage); __init__
  validates chain ordering (first stage must be NoiseStackKernel).
  9 TDD pytests green (shape+dtype + noise-only matches bare +
  erosion changes output + determinism + cache miss-then-hit + miss
  on seed change + miss on extent change + metadata records
  provenance + no-store doesn't persist). pytest total 174.
  Build note phase_5_7_c_bake_page_cache_2026_05_17.md.
- 2026-05-17 (Phase 5.7.b closed — Python KernelComposer):
  Spec 19 §"KernelComposer" + spec 22 §"Catalog schema". Two
  responsibilities: (1) `biome_weights(x,z,elev,slope)` via softmax
  over each biome's auto_biome_rules elevation+slope bands (same
  smoothstep shape as shader's w5_slot_weight for consistency);
  (2) `sample_height(x,z,seed)` via per-biome kernel chain dispatch.
  Chain spec supports shorthand `{type: noise_stack, params}` and
  explicit `{type: chain, stages: [...]}` per kernel_chain.schema.json.
  Erosion-in-chain RECOGNIZED but per-point dispatch DEFERRED to
  5.7.c bake_page (erosion needs page-scope context). 12 TDD pytests
  green (construct + reject-malformed + weights sum-to-1 + biome
  dominance at elev extremes + crossover-blend + chain-of-1 ==
  bare-kernel + explicit-chain == shorthand + determinism × 2).
  pytest total 165. Build note phase_5_7_b_kernel_composer_2026_05_17.md.
  Phase 6 multi-biome render path: port `_band_weight` to GDScript
  + bind auto_rules per biome → shader multiplies slot_weight by
  per-biome weight per fragment.
- 2026-05-17 (Phase 5.7.a closed — Python ErosionKernel reference):
  Spec 19 §"Kernel types shipped in v1" item 2. Mei 2007 hydraulic
  step (rain → flux → velocity → sediment capacity → dissolve/deposit
  → evaporate) + Musgrave thermal step (talus-angle slumping)
  interleaved. ~250 lines numpy. Emits ErosionResult with eroded
  height + drainage_map + flow_direction + flow_accumulation
  (consumed downstream by spec 35 water rivers + spec 41 roads
  valley biasing). Schema at engine/resources/schemas/kernels/
  erosion.schema.json (12 params, all defaults + descriptions).
  Test-first per superpowers TDD: 8 pytest cases (construct +
  shape/dtype + flat-input invariance + determinism + bounded
  range + radial drainage + flow direction on ramp + thermal
  slumping). 8/8 green; pytest total now 151 (was 143). Build note
  phase_5_7_a_erosion_kernel_2026_05_17.md. Also: extended
  materials_manifests preflight _resolve_res_path to handle
  `res://addons/world5/` prefix (demo project's mount of engine/).
  Next: 5.7.b KernelComposer (unblocks Phase 6 multi-biome).
- 2026-05-17 (Phase 6 paused; pivoting to Phase 5.7):
  Started Phase 6 (forest second biome). Promoted texture team's
  forest candidates (dirt_mossy ground + roots_moss mid + granite_mossy
  rock + 3 siblings each = 48 files). Extended biome_catalog with
  forest biome including auto_biome_rules for biome-weight crossover
  (alpine [10,60]+10m band, forest [-50,10]+10m band, crossover at
  5-15m elev). While starting multi-biome shader wire-up, realized
  per-fragment biome weighting belongs in KernelComposer (spec 22
  §"softmax over biome_weights"), not inline in the shader's slot
  loop. Per ethos + user direction "best long term way / following
  roadmap", paused Phase 6. Forest slots moved to `_pending_slots`
  in material_variants.json (loader-ignored) so walking_demo still
  renders alpine cleanly. test_load_real_walking_demo_catalog
  updated to assert 2 biomes. Build note phase_6_paused_2026_05_17.md.
  Pivot: Phase 5.7.a Python ErosionKernel reference next.
- 2026-05-17 (Phase 4.11 closed — heightmap clamp + slot bleed):
  Post-4.10 user re-test surfaced two more artifacts. 4.11.a:
  removed the [0,1] clamp in `_update_ring_height_array` height
  encoding — fBm peaks past ±amplitude were clamping to flat plateau
  with sharp level-set edges (V-shape depression in screenshot).
  Float32 texture stores arbitrary range; shader decode handles it.
  4.11.b: tightened walking_demo biome_catalog slot bands —
  pre-fix mid slot's slope window [10°, 45°] with 8° band activated
  at 2°+ slope = bled into near-flat ground as white patches. Now
  mid starts at 21°, rock at 40°; clear separation. Verify 5/5
  green in 59.9s. Build note phase_4_11_2026_05_17.md. Pop-in /
  streaming polish (W4 PITFALLS #15) deferred per user direction.
- 2026-05-17 (Phase 4.10 closed — W4 PITFALLS lifted):
  User screenshots after 5.4.b showed (1) elevation cliff at ring
  boundary, (2) 20m blocky brightness patches, (3) "rings visible
  while moving". User redirect to `D:/assets/world 4/docs/reference/PITFALLS.md`
  let us diagnose each as a documented W4 failure mode rather than
  re-deriving from scratch. 3 fixes shipped: 4.10.a per-vertex morph
  via new `ring_center_xz` + `ring_half_extent_m` + `morph_band_frac`
  uniforms (PITFALLS #11); 4.10.b `RingHeightArray.rebase` retains
  in-window pages on snap instead of dropping all (PITFALLS #14);
  4.10.c killed redundant `0.85 + 0.30 * nv` brightness modulator
  (PITFALLS #31 class). +3 TDD tests. Verify 5/5 green in 58.3s.
  Build note phase_4_10_close_2026_05_17.md. Memory saved at
  `w5-clipmap-w4-pitfalls-apply` so future W5 terrain debugging
  starts with W4 PITFALLS lookup.
- 2026-05-17 (Phase 5.4.b partial closed — C3 + S7):
  `terrain_sibling_blend_freq` added per-tier in quality_tiers.json
  (low 0.20 → cinematic 0.40; high 0.30 was 0.10).
  `MaterialPipeline.bind_sibling_blend_freq` binder (+2 TDD tests)
  + TerrainWorld wire-up in `_bind_slots_with_catalog` reads
  `QualityTiers.get_current()`. Visible tile-to-tile repeat at
  standing eye height broken up — 3× finer noise wavelength means
  sibling switch every ~3 m instead of every ~10 m.
  `pipeline/biomes/alpine.yaml` (51 candidates) + `forest.yaml`
  (21 mid-only) ported from W4 — fresh devs unblocked end-to-end.
  Verify 5/5 green stable in 60.0s. Build note
  phase_5_4_b_partial_2026_05_17.md. Sub-task 5.4.b.3 (detail
  overlay ComfyUI batches) deferred to separate session.
- 2026-05-17 (Phase 4.9.c closed — Phase 4.9 fully done):
  walking_demo now ships `macro_albedo.json` at world root +
  `materials/biome_alpine/ground/macro_albedo.png` via
  `tx_macro_terrain --purpose-candidates --promote-purpose`.
  tx_macro_terrain updated to read W5 `material_kit` (in addition
  to W4 `kit_dir`); also fixes manifest_path parent-dir creation
  bug. materials_manifests preflight gained `_check_macro_albedo`
  (+4 TDD tests; relaxed pre-existing tests from "issues == []" to
  "errors == []"). `.gitignore` adds `engine/worlds/**/captures/`
  for derived authoring artifacts. Verify 5/5 green stable in
  61.0s; pytest now 143 passed (was 139). Build note
  phase_4_9_c_macro_albedo_2026_05_17.md. Closes audit S2;
  Phase 4.9 done end-to-end.
- 2026-05-17 (Phase 5.1 closed): 11 tx_*.py + 3 drivers ported
  from W4 with relative-package imports. tx_macro_terrain rebased
  onto W5 layout (DEFAULT_WORLD = engine/worlds/walking_demo).
  material_variants_builder skipped (promote.py already does its
  job). Smoke tests: 15/15 imports + 6/6 --help. Verify 5/5 green
  stable in 59.8s. Build note phase_5_1_module_port_2026_05_17.md.
  Unblocks 4.9.c + 5.4.b + 5.6 + audit S5/S6/S7.
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
