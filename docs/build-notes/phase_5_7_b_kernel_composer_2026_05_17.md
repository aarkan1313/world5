# Phase 5.7.b — KernelComposer (Python reference, partial) — DONE 2026-05-17

> Phase: 5.7.b (second sub-task of Phase 5.7 erosion sprint family)
> Status: ✅ done 2026-05-17 (Python reference; GDScript runtime
> mirror + bake_page erosion dispatch deferred to 5.7.c)
> Plan: [phase_5_7_erosion_sprint.md](../roadmap/phase_5_7_erosion_sprint.md)
> Schema: [kernel_chain.schema.json](../../engine/resources/schemas/kernels/kernel_chain.schema.json)
> Driven by: spec 19 §"KernelComposer" + spec 22 §"Catalog schema" +
> Phase 6 multi-biome render pause on per-fragment biome_weights

## What shipped

The **Python reference** of KernelComposer per spec 19. The
architecturally-load-bearing piece that unblocks Phase 6 multi-biome
rendering: it turns a biome catalog into a function over (x, z) →
(height, biome_weights).

### Files

| File | Purpose |
|---|---|
| `engine/resources/schemas/kernels/kernel_chain.schema.json` | Spec for the biome's `kernel` field. Single-stage shorthand (`{type: 'noise_stack', params}`) OR explicit chain (`{type: 'chain', stages: [...]}`). 1-8 stages, first stage must be a base generator. |
| `pipeline/world5/kernels/composer.py` | `KernelComposer` class + helpers (`_band_weight`, `_normalize_chain`, `_instantiate_stage`). ~200 lines. |
| `pipeline/world5/kernels/__init__.py` | Re-exports `KernelComposer`. |
| `tests/unit/test_kernel_composer.py` | 12 pytest cases covering construct + reject-malformed-catalogs + biome weights (sum + dominance + crossover) + height composition (finite + chain-of-1 == bare kernel) + explicit chain dispatch + determinism. Test-first per superpowers TDD. |

### Two responsibilities (per spec 22 §Catalog schema)

**1. `biome_weights(x, z, elev_m, slope_deg) -> ndarray[biome_count]`**

The piece Phase 6 needs. Computes per-(x,z,elev,slope) selection
probabilities by:
- For each biome, evaluating `_band_weight(elev, slope, auto_rule)` —
  smoothstep ramp-in + ramp-out on both axes, product across axes.
  Same shape as the shader's `w5_slot_weight` for consistency.
- Sum-normalize so output sums to 1 (probability distribution).
- Fall back to uniform across biomes if NO biome's auto_rule covers
  the (elev, slope) — renderer still picks something instead of
  black/null.

This is what the renderer will multiply by per-slot weights to
compute `final_material = Σᵢ biome_weights[i] × slot_weight_within_biome[s] × sibling_blend[s]`.

**2. `sample_height(x, z, seed) -> float`**

Dispatches each biome's kernel chain via `_sample_chain`. Chain
dispatch supports both shorthand and explicit forms:
- `{type: 'noise_stack', params: ...}` → chain of length 1
- `{type: 'chain', stages: [{type: 'noise_stack', ...}, ...]}` → explicit

Erosion stages in a chain are RECOGNIZED at parse time (no construct
failure) but DEFERRED at evaluation time. The Composer's per-point
`sample_height` skips erosion stages because erosion needs page-scope
context (it's a stencil over a whole heightmap, not a per-point
function). The `bake_page` entry point that runs erosion stages on
whole pages lands with 5.7.c content-addressed cache.

### Test coverage (12/12 green)

| Category | Test | Proves |
|---|---|---|
| Construct | `test_constructible_from_walking_demo_catalog` | Reads real walking_demo catalog (alpine + forest) successfully |
| Construct | `test_construct_rejects_catalog_with_no_biomes` | Validates required `biomes` array |
| Construct | `test_construct_rejects_missing_kernel_field` | Validates required per-biome `kernel` field |
| Weights | `test_biome_weights_sum_to_one_at_arbitrary_points` | Probability distribution invariant at 20 random (x,z) |
| Weights | `test_forest_dominates_low_elevation` | At elev=-30, forest weight ≥ 0.9 (alpine should be tiny) |
| Weights | `test_alpine_dominates_high_elevation` | At elev=40, alpine weight ≥ 0.9 |
| Weights | `test_crossover_band_blends_both_biomes` | At elev=10 (crossover midpoint), both biomes ≥ 0.1 |
| Height | `test_sample_height_returns_finite_scalar` | No NaN/Inf, within kernel amplitude (±100m guard) |
| Height | `test_chain_of_one_matches_bare_noise_stack` | Composer's height == bare `NoiseStackKernel.sample_page` at the same (x,z,seed) |
| Chain | `test_explicit_chain_dispatch_runs_stages_in_order` | Shorthand and explicit chain forms produce identical output |
| Determinism | `test_deterministic_for_same_inputs` | Same (x,z,seed) → byte-identical |
| Determinism | `test_different_seed_changes_height` | Different seed → different output (sanity) |

## What's NOT in this sub-task

Deliberately deferred to keep the scope tight + ship the unblock-Phase-6
piece first:

- **GDScript runtime mirror** of `KernelComposer.biome_weights` — the
  binding-side counterpart that the renderer calls per fragment.
  Two options for delivery (the next sub-sprint picks):
  1. Bake the biome_weights as a low-res world-spanning texture
     (e.g. 128×128 covering ±2km) → shader samples at world XZ → blend.
     Lower runtime cost, requires a bake step.
  2. Re-implement `_band_weight` softmax in GDScript + run per fragment.
     Simpler, more runtime cost (small for biome_count ≤ 4).
- **`bake_page(world_origin, extent, grid_n, seed)`** — the entry
  point that runs erosion stages on a whole page. Needs the spec 12
  content-addressed cache wired (5.7.c) before it's useful.
- **Multi-biome height blending** — currently uniform average across
  biomes. When chains diverge per biome (e.g. alpine with erosion
  vs forest with plain noise), `sample_height` will need to weight
  by `biome_weights(x, z, h_estimate, slope_estimate)`. Walking demo
  uses identical noise_stack in both biomes today, so this is moot.
- **Schema validation** — kernel_chain.schema.json exists but no
  runtime validator wired. Catalog-load validation is currently
  shape-only inside `KernelComposer.__init__` (recognizes the
  required fields; raises ValueError on malformed). Full jsonschema
  validation lands when world_contract gets a schema-driven layer.

## How Phase 6 resumes

With KernelComposer Python reference in place, Phase 6 multi-biome
render needs ONE of:

1. **Per-fragment Composer in GDScript** (option B above): port
   `_band_weight` to GDScript + add a binder to MaterialPipeline +
   shader uniforms `biome_auto_elev_bands[MAX_BIOMES]`,
   `biome_auto_slope_bands[MAX_BIOMES]`, `biome_count`. Fragment
   computes `biome_w[i]` itself per fragment, multiplies the slot
   weight by it.

2. **Baked biome_weight texture** (option A above): KernelComposer
   bakes a per-world `biome_weights.exr` (128×128 × biome_count
   channels) → texture bound to all rings → fragment samples world
   XZ → reads weights. Composer's `bake_page` entry point handles
   this.

Recommend option 1 for first cut (avoids new bake step + new cache
file; per-fragment math is cheap for ≤ 4 biomes). Option 2 becomes
attractive when biome_count > 4 OR auto_rules get expensive (e.g.
moisture + climate kernels factored in).

When Phase 6 ships option 1, the `_pending_slots` array in
walking_demo's `material_variants.json` moves back into `slots` —
per `docs/build-notes/phase_6_paused_2026_05_17.md`.

## Verify status

`pytest tests/unit/test_kernel_composer.py -v` → 12/12 green in ~0.14s.
`python -m world5.verify --fastest` → 165 pytest passed (was 151 →
+12 KernelComposer + 2 in-flight new tests).

(NOTE: gut_real_gpu still failing on cinematic-tier calibration per
the prior session's diagnosis — that's the in-flight Phase 5.6
budget pass's perf-assertion mismatch, NOT Phase 5.7.b. Pure
Python additions don't touch GPU.)

## Spec 19 sub-sprint status

| Sub-sprint | Status |
|---|---|
| 5.7.a Python ErosionKernel reference | ✅ done (commit `92ef039`) |
| **5.7.b Python KernelComposer** | **✅ done (this build note)** |
| 5.7.c Cache integration (spec 12 content-addressed bake_page) | pending |
| 5.7.d GPU compute port of ErosionKernel | deferred (optional; only when Python perf is the bottleneck) |
| 5.7.e DemFeatureKernel | deferred (its own sprint per spec 19 amendment) |

## Doc cap status

~165 lines (under 350 cap).
