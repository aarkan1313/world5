# Phase 5.7 demonstration — walking_demo erosion bake (DONE 2026-05-17)

> Phase: 5.7 (demonstration close; not a new sub-sprint)
> Status: ✅ done 2026-05-17
> Closes: the Phase 5.7 demonstration gap flagged in the
> roadmap-alignment audit (5.7.a + 5.7.b + 5.7.c shipped the parts;
> this proves they assemble + run on a real catalog)

## What shipped

End-to-end proof that the Phase 5.7 kernel system works on the
real walking_demo catalog:
1. Walking_demo's alpine biome now declares an explicit kernel chain
   (`noise_stack` + `erosion`) in `biome_catalog.json` per the spec
   19 chain spec
2. `pipeline/world5/demo/bake_walking_demo_erosion.py` runs
   `KernelComposer.bake_page` on a 1km² alpine region, comparing
   eroded vs noise-only baseline
3. Spec 12 content-addressed cache verified end-to-end: second bake
   ran 766× faster than first (cache hit, no recompute)
4. Visual comparison PNG saved at
   `engine/worlds/walking_demo/captures/erosion_comparison.png` —
   side-by-side hillshade (left: noise-only, right: eroded)

### Measured numbers (5090 dev rig)

| Metric | Value |
|---|---|
| First bake (50 hydraulic + 20 thermal iterations) | 0.19s on 256×256 grid (1km², 4m cells) |
| Bumped bake (400 hydraulic + 100 thermal) | 0.77s on same grid |
| Cache hit (re-bake unchanged inputs) | 0.001s — sub-millisecond, 766× speedup |
| Noise-only baseline (bypassing Composer) | 0.03s |
| Mean abs(eroded - noise_only) | 0.060m |
| Max abs(eroded - noise_only) | 1.72m |
| Cells changed by > 0.5m | 1901 of 65536 (2.9%) |

The 1.72m max delta on a 50m amplitude terrain is ~3.5% — visible
softening of peaks + emerging drainage gullies. Not dramatic
canyon carving (would need 5000+ iterations + bigger sediment
capacity) but clearly demonstrates erosion is running + producing
geologically-shaped output.

### Files

| File | Change |
|---|---|
| `engine/worlds/walking_demo/biome_catalog.json` | Alpine biome's `kernel` field upgraded from flat noise_stack to explicit chain (noise_stack + erosion stages). 400 iterations / 100 thermal / talus_angle 35°. Documented with `_kernel_note` + per-stage `_note` annotations. |
| `pipeline/world5/demo/__init__.py` | NEW — package for phase-demonstration scripts |
| `pipeline/world5/demo/bake_walking_demo_erosion.py` | NEW — the bake script. Reads catalog, builds Composer, calls bake_page twice (verifies cache hit), bakes noise-only baseline via bare kernel, renders hillshade comparison + JSON manifest. ~220 lines. |
| `engine/worlds/walking_demo/captures/erosion_comparison.png` | NEW (gitignored per existing `engine/worlds/**/captures/` rule) — visual hillshade comparison |
| `engine/worlds/walking_demo/captures/erosion_comparison.json` | NEW (gitignored) — manifest with all measured numbers + provenance |

### Runtime wiring NOT in this demo

The walking_demo TerrainWorld runtime loader still reads
`engine/worlds/walking_demo/kernels/noise_stack.json` directly,
NOT the catalog's `kernel` field. The catalog's chain declaration
is correct + parseable + bakes correctly via the Composer; but the
live walking_demo render still uses the noise-only kernel because
the loader switch hasn't happened.

That loader switch (read kernel from catalog instead of noise_stack.json,
preferring cached bake_page output when available) is a separate
~1-2 session refactor. Reasons to defer:

1. It touches TerrainWorld's GPU page generation path — exactly the
   territory where the other chat had a Godot-engine crash recently;
   safer to let in-flight Godot work settle first
2. The current Phase 6 unblocker (GDScript biome_weights mirror) is
   a higher-priority Godot-side refactor; pairing them lets the
   loader switch + Composer wire-up land together
3. The demo script proves the parts work without needing the wire-up

When the loader switch ships, walking_demo will render the eroded
alpine terrain natively at startup (cache hit on every subsequent
load).

### What this validates

Per the Phase 5.7 roadmap-alignment concern I flagged
("ErosionKernel has not been demonstrated on a real catalog"):

- ✅ ErosionKernel runs on a real walking_demo catalog (not just
  test fixtures)
- ✅ KernelComposer's chain dispatch correctly identifies the
  noise_stack base + runs erosion as post-process
- ✅ KernelComposer.bake_page works end-to-end with a real
  ContentAddressStore on disk
- ✅ Spec 12 content-addressed cache provides massive (>700×)
  speedup on cache hits
- ✅ Erosion visibly changes terrain shape (1.72m max delta, 2.9%
  of cells); chain isn't a no-op
- ✅ The catalog kernel-chain schema (`kernel_chain.schema.json`)
  matches what real catalogs need

## How to re-run

```bash
python -m world5.demo.bake_walking_demo_erosion
```

Idempotent — second run hits the cache + finishes in < 100ms total
(both bakes + PNG rendering). Edit `iterations` or `rain_rate` in
the catalog to change the eroded output; cache invalidates
automatically (catalog hash differs).

## Phase 5.7 sub-sprint status post-demonstration

| Sub-sprint | Status |
|---|---|
| 5.7.a Python ErosionKernel reference | ✅ `92ef039` |
| 5.7.b Python KernelComposer | ✅ `c9838da` |
| 5.7.c bake_page + cache + erosion-in-chain | ✅ `937710b` |
| **5.7 demonstration (this build note)** | **✅ proves end-to-end on walking_demo** |
| 5.7.d GPU compute port | deferred (Python ref is fast enough; 0.77s for 400-iter on 1km² is well under spec 19's 60s bake target) |
| 5.7.e DemFeatureKernel | deferred (no consumer yet) |
| TerrainWorld loader switch (catalog-driven kernel) | next, paired with the GDScript biome_weights mirror for Phase 6 |

## Doc cap status

~140 lines (under 350 cap).
