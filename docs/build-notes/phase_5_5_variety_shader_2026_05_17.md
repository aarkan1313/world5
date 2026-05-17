# Phase 5.5 — Variety shader Layer 1 + Layer 2

> Date: 2026-05-17
> Closes: Phase 5.5 (spec 24 Layers 1 + 2 shader infrastructure)
> Opens: nothing new — clears the runway for Phase 5.4 texture binding
>        once the in-flight texture authoring completes

Phase 5.5 was authored ahead of Phase 5.4 (first-biome texture run)
because the shader work is non-conflicting with the in-flight W4
texture-pipeline cleanup happening in a parallel chat. When textures
land, Phase 5.4 promotion will flip `has_siblings`/`has_detail` on
without further shader edits.

## What shipped

**Shader primitives** in `engine/shaders/variety_common.gdshaderinc`:
- `w5_variety_sample_3tap(sampler2DArray, tile_uv, world_xz, start, count, blend_freq) -> vec4`
  Heitz-Neyret 2018 simplified. Samples 3 offset UVs from 3 noise-
  selected layers, blends by softmax-weighted noise. Returns rgb+a.
- `w5_detail_blend(sampler2DArray, tile_uv, world_xz, count, blend_freq) -> vec4`
  2-tap overlay blend; weights = alpha + 0.05 so high-coverage details
  dominate. Returns rgb (blended color) + a (combined coverage).

**Fragment-shader wiring** in `engine/shaders/terrain_clipmap.gdshader`:
- New uniforms: `sampler2DArray sibling_array` + `int sibling_start`
  + `int sibling_count` + `bool has_siblings` + `float sibling_tile_m`
  + `float sibling_blend_freq` (Layer 1)
- `sampler2DArray detail_array` + `int detail_count` +
  `bool has_detail` + `float detail_tile_m` + `float detail_blend_freq`
  + `float detail_strength` (Layer 2)
- Optional fragment paths gated by `has_*` flags — unbound flag
  defaults preserve the pre-5.5 macro-only render so the walking demo
  still works today before textures arrive

**MaterialPipeline binders** in
`engine/scripts/terrain/material/MaterialPipeline.gd`:
- `bind_sibling_array(mat, Texture2DArray, start_index, count)` —
  flips `has_siblings = true`; clamps count to `SIBLING_COUNT_CAP = 8`
  (spec 24 shader cap)
- `bind_detail_array(mat, Texture2DArray, count)` — flips
  `has_detail = true`; refuses null array or count ≤ 0

**Tests** — TDD per superpowers rule, every primitive + binder driven
by a failing test before code was written:
- `engine/tests/unit/test_material_pipeline.gd` (+5 new tests for
  Layer 1 + Layer 2 binders → 13 total in file)
- `engine/tests/unit/test_variety_common_shader.gd` (NEW; 7 tests
  asserting shader-text references for both layers)
- `engine/tests/integration/test_variety_layers_real_device.gd` (NEW;
  4 real-GPU tests: shader-loads + binder-doesn't-crash-draw for
  both layers + behavioral assertion that sibling-bound render
  measurably differs from macro-only fallback via per-channel color
  delta)

## What did NOT ship

- Real ground textures (user authoring offline; Phase 5.4)
- Per-fragment slot selection — Phase 5.5 ships single-active-slot
  (Phase 6 multi-biome will widen `sibling_start` + `sibling_count`
  from scalars to per-slot arrays)
- Normal-map siblings — current binder is single-array (albedo).
  Phase 5.4+ may add a `bind_sibling_normal_array()` against the same
  `start/count` window
- Macro `--purpose-candidates` regeneration — that's Phase 5.4 step 5

## Verify status

5/5 layers green stable in 47s:
- pytest 115 passed
- gut headless all passed
- gut_real_gpu all passed (including the 4 new Phase 5.5 integration
  tests; the behavioral test confirms Layer 1 actually samples on GPU
  by measuring per-channel deltas between bound + unbound renders)
- preflight 0 errors / 0 warnings
- capture all passed (no regression in baseline)

## What's load-bearing post-5.5

- `MaterialPipeline.bind_sibling_array()` is the single entry point
  for routing Phase 5.4's promoted sibling pool into the runtime
  shader. `promote.py` (Phase 5.2 deliverable) writes the
  material_variants.json that drives this binder.
- `terrain_clipmap.gdshader`'s `has_siblings`/`has_detail` gates are
  the only place the shader branches on Phase 5 availability — any
  new Layer 1+2 features (normal-map siblings, per-slot weights)
  must respect the same default-off contract so the walking demo
  doesn't regress before textures arrive
- `variety_common.gdshaderinc` is shared across terrain + (future)
  water/decoration; the 3-tap + detail-blend primitives are
  consumer-facing API. Renaming or signature changes are
  contract-breaking.

## Investigation closed

The Phase 4 doc sweep flagged uncertainty about whether the verify
CLI's `gut_actually_failed` parser correctly catches real gut
failures. Confirmed by injecting a deliberate `assert_eq(1, 2)` —
verify returned exit 2 + `[FAIL] gut` + `gut_actually_failed: True`.
Parser works as designed; earlier confusion was misreading the
parse-error case (file failed to load, no test ran, gut still
reported a different test's failure from the same suite).

## Parallel-chat coordination note

Pre-Phase 5.5 the plan called for 5.1 first (port W4 `tx_*.py`
modules). Bailed out after copying the 11 files when `git status` on
W4's working tree showed another chat is actively modifying
`pipeline/textures/{tx_macro_terrain, experiment_audit_matrix,
README}.py` + all four `pipeline/diversity_*.py` drivers. Copying
now would snapshot a stale tree.

W4 is also 312 commits ahead of origin/main locally — coordination
across chats requires either (a) the other chat pushing first, (b)
explicit handoff, or (c) doing W5-only work that doesn't touch W4
sources. Picked (c) for this session: Phase 5.5 is pure W5 shader
code, zero W4 imports.

Phase 5.1 stays held pending the other chat's W4 work landing on
origin/main.

## Doc cap status

~115 lines (well under 350 build-note cap).
