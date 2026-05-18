# Phase 5.7.c — bake_page + erosion-in-chain dispatch + cache (DONE 2026-05-17)

> Phase: 5.7.c (third sub-task of Phase 5.7 erosion sprint family)
> Status: ✅ done 2026-05-17
> Plan: [phase_5_7_erosion_sprint.md](../roadmap/phase_5_7_erosion_sprint.md)
> Depends on: 5.7.a ErosionKernel + 5.7.b KernelComposer (both shipped)
> Driven by: spec 19 §"Pre-bake global pass" + spec 12 content addressing

## What shipped

`KernelComposer.bake_page()` — the entry point that runs a biome's
full kernel chain (noise_stack base + erosion post-process) on a
WHOLE page. This is the missing piece from 5.7.b where erosion
stages were recognized at construct time but skipped at per-point
sample (erosion is intrinsically page-scope, can't be evaluated at
a single XZ).

With bake_page in place, real walking_demo catalogs can now declare
chains like:

```json
"kernel": {
  "type": "chain",
  "stages": [
    {"type": "noise_stack", "params": {...}},
    {"type": "erosion", "params": {"iterations": 100, ...}}
  ]
}
```

…and the Composer will execute the chain in order. Output is
optionally cached via spec 12 ContentAddressStore so re-bakes with
unchanged inputs skip recompute.

### Files

| File | Change |
|---|---|
| `pipeline/world5/kernels/composer.py` | + `bake_page(world_origin, extent, grid_n, seed, store=None, biome_index=0)` + `_run_chain_on_page` + `_page_cache_key` + `_hash_catalog` + `_load_page_bytes` + `_DummyHasher`. Also: `_instantiate_stage` no longer raises on erosion (returns a usable `ErosionKernel`); `__init__` validates chain ordering (first stage must be base generator); dropped `_DeferredStage` placeholder. |
| `tests/unit/test_kernel_composer_bake.py` | NEW — 9 TDD tests for bake_page (RED → GREEN). |

### Test coverage (9/9 green)

| Test | Proves |
|---|---|
| `test_bake_page_returns_grid_shaped_float32` | API contract: (grid_n, grid_n) float32 array |
| `test_bake_page_noise_only_matches_bare_kernel` | Noise-only chain (no erosion) bakes identically to `NoiseStackKernel.sample_page` |
| `test_bake_page_with_erosion_changes_output_vs_noise_only` | Erosion stage in chain actually runs (>50 cells differ by >0.01m vs no-erosion baseline) |
| `test_bake_page_deterministic_same_inputs` | Same (world_origin, extent, grid, seed) → byte-identical output |
| `test_bake_page_cache_miss_then_hit` | 1st call writes 1 artifact; 2nd call with same inputs is a HIT (still 1 artifact) |
| `test_bake_page_cache_miss_on_seed_change` | Different seed → different cache key → 2 artifacts |
| `test_bake_page_cache_miss_on_extent_change` | Different extent → different cache key → 2 artifacts |
| `test_bake_page_cache_metadata_records_provenance` | Cache metadata records catalog_hash + biome + world_origin + extent + grid + seed (auditable) |
| `test_bake_page_no_store_does_not_persist` | `store=None` path runs but writes nothing — useful for tests + one-off bakes |

### Cache key shape

The bake's content-address key is `sha256(canonical_json({
  kind: "kernel_composer.bake_page",
  catalog_hash: <sha256 of the whole catalog JSON>,
  biome: <name>,
  world_origin_x, world_origin_z: floats,
  extent_m, grid_n: float/int,
  seed: int,
}))`.

The `catalog_hash` inclusion means **any edit to the catalog
invalidates all baked pages from that catalog**. Tighter than
strictly necessary (an unrelated biome's param change still
invalidates this biome's bakes), but matches spec 12's strict
input-dependency model — false-positive evictions are cheap (re-bake)
versus false-negative reads (stale data) which are silent bugs.

Cache eviction is automatic via `ContentAddressStore.gc_if_over_cap()`
triggered on every put (per SA-S2.4 default cap = 20 GB).

## Performance notes

`bake_page` perf is dominated by the chain's most expensive stage.
For walking_demo's iteration-light test fixture (`iterations=10,
thermal_iterations=5`), a 16² grid bakes in ~5-10ms; the real spec-19
target case (1024² grid, ~100 iterations) extrapolates to ~30-60s
per page bake on the Python reference. The cache means this cost is
paid ONCE per (catalog, world_origin, extent, grid, seed) tuple over
the world's lifetime.

This is the per-page version of the spec 19 §"Pre-bake global pass"
contract. A future world_contract pre-bake step will iterate all
required pages at bundle install time + warm the cache; runtime
sampling becomes pure cache reads.

## What's NOT in 5.7.c (still deferred)

- **Auxiliary outputs from cached bakes**: ErosionKernel emits
  drainage_map + flow_direction + flow_accumulation alongside the
  eroded height. `bake_page` currently caches ONLY the eroded
  height. Spec 35 water (rivers) + spec 41 roads will need a
  parallel `bake_page_auxiliary(...)` (or an extended `bake_page`)
  that caches the auxiliary fields too. Deferred until a real
  consumer asks.
- **Global-bake pass**: spec 19 §"Pre-bake global pass" envisions
  baking the WHOLE world's height in one numpy pass for ≤ 10km²
  worlds (tile-mode for larger). Currently bake_page is the only
  entry point; consumers iterate per-page. Global bake is a thin
  wrapper that lands when a consumer needs the all-at-once form.
- **GDScript runtime mirror of `biome_weights`**: still deferred.
  This is what unblocks Phase 6 multi-biome render. Independent of
  5.7.c — the renderer reads cached BAKED pages for terrain shape,
  but the per-fragment biome material blend needs the GDScript
  port of `_band_weight` softmax. Tracked separately.

## Phase 5.7 sub-sprint status post-5.7.c

| Sub-sprint | Status |
|---|---|
| 5.7.a Python ErosionKernel reference | ✅ commit `92ef039` |
| 5.7.b Python KernelComposer | ✅ commit `c9838da` |
| **5.7.c bake_page + cache + erosion-in-chain** | **✅ this build note** |
| 5.7.d GPU compute port of ErosionKernel | deferred (optional; Python ref hits the spec 19 bake target) |
| 5.7.e DemFeatureKernel | deferred (no consumer yet) |
| GDScript biome_weights mirror (Phase 6 unblocker) | next, **not** part of 5.7 sprint per the original plan |

## What Phase 6 needs to resume (unchanged from 5.7.b note)

1. GDScript port of `_band_weight` softmax → MaterialPipeline binder
   for per-biome auto_rules → shader multiplies slot_weight by
   biome_weight per fragment.
2. Move forest entries from `_pending_slots` → `slots` in
   walking_demo's `material_variants.json`.

Phase 6 does NOT need erosion in walking_demo's catalog to ship —
walking_demo can stay noise-only while still validating multi-biome.
Erosion-in-catalog lands when the user wants real geological terrain
shape; 5.7.c made it possible but not required.

## Verify status

`python -m pytest tests/unit/test_kernel_composer_bake.py -v` →
9/9 green in 0.29s.
`python -m world5.verify --fastest` → **174 pytest passed** (was
165 → +9 bake_page tests).

(NOTE: gut_real_gpu still failing on cinematic-tier calibration —
in-flight Phase 5.6 budget pass territory, not 5.7. Pure Python
additions in this sub-task don't touch the GPU layer.)

## Doc cap status

~170 lines (under 350 cap).
