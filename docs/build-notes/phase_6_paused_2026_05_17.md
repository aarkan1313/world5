# Phase 6 (forest) — PAUSED 2026-05-17

> Phase: 6 (second biome — forest)
> Status: ⏸ paused 2026-05-17 (test fixtures landed; render gated on 5.7.b)
> Reason: Multi-biome rendering needs `KernelComposer` first per
> spec 22 + roadmap dependency graph + user direction
> ("best long term way / following roadmap")

## What landed (kept on disk as test fixture)

- **Forest textures promoted** to
  `engine/worlds/walking_demo/materials/biome_forest/` via
  `python -m world5.textures.promote --biome forest --slot ground
  --base dirt_mossy_base --siblings dirt_mossy_s43 _s44 _s45
  --slot mid --base roots_moss_base --siblings roots_moss_s43 _s44 _s45
  --slot rock --base granite_mossy_base --siblings granite_mossy_s43 _s44 _s45`.
  48 files copied, 9 sibling entries added to `material_variants.json`.
- **`material_variants.json` extended** from 3 alpine slots to 6
  slots total (alpine + forest, 4 variants each = 24 layers; under
  the 256-layer cap with plenty of headroom).
- **`biome_catalog.json` extended** with the `forest` biome entry:
  full `surface_slots` for ground/mid/rock with selector bands,
  `auto_biome_rules` for biome-weight crossover, climate_base, etc.
  Alpine's `auto_biome_rules` also updated from the previous
  `[-50, 50] / [0, 90]` (which meant "alpine owns everywhere") to
  `[10, 60]` elev with a 10m band — proper bounded ownership.
  Crossover with forest sits at elev 5-15m via the two 10m bands.

These are NOT rendered yet — they're the test fixture for
`KernelComposer` (Phase 5.7.b) to validate against.

## Why we paused

While starting the multi-biome shader wire-up, the architectural
shape revealed a problem: per-fragment biome weighting is a
**KernelComposer concern**, not a per-slot shader concern.

Per spec 19 §"KernelComposer" + spec 22 §"Catalog schema":
> KernelComposer blends per-biome kernels via softmax over
> biome_weights from biome catalog. Produces unified (height,
> weights) at any (x, z).

The biome weights are the canonical per-(x,z) blend factors;
materials, terrain height, decoration, AND audio_tag selection all
consume them. Inlining biome weighting into the shader's slot loop
(as I was about to do, multiplying `slot_weight × biome_weight`
piggybacked onto the existing `bind_all_slots` data path) would:

1. Create a parallel implementation that 5.7.b later replaces
   (wasted shader work)
2. Skip the cache benefit (5.7.c content-addresses Composer output;
   inline shader computation never caches)
3. Block proper biome-driven height crossover (alpine vs forest at
   the same XZ should be able to use different kernel chains;
   shader can't blend kernels, only the Composer can)

Per project ethos memory `project_ethos_quality_first` ("Quality ≥
Performance > anything else > time-to-ship; always pick
architecturally-correct even if more sessions") and user direction
2026-05-17 ("lets do this the best long term way / following
roadmap"), the call is: **don't inline. Build Composer first.**

## What needs to ship before Phase 6 resumes

Per `docs/roadmap/phase_5_7_erosion_sprint.md`:
- **5.7.a Python ErosionKernel reference** — the parity ground truth
  for the kernel system. Even without erosion in walking_demo's
  current scope, Phase 6 multi-biome work proves out the Composer
  contract — so Composer needs ErosionKernel (or at least the Kernel
  base contract) operational
- **5.7.b KernelComposer** — Python + GDScript. Reads biome
  catalog's per-biome kernel chain. Computes per-(x,z) biome_weights
  via softmax over auto_biome_rules. Caches output per spec 12.
  THIS is what unblocks Phase 6's multi-biome rendering
- 5.7.c (cache integration) ideally lands too so re-bakes don't
  thrash

Once 5.7.b ships, Phase 6 resumes with:
- TerrainWorld reads cached Composer output → per-fragment
  biome_weight texture bound on every ring's material
- Shader's slot loop multiplies `slot_weight × biome_weight[slot.biome_index]`
- Both biomes' slot bands stay active simultaneously; per-fragment
  biome_weight picks which biome dominates → no inline shader hacks

## What this proves about the roadmap

This is exactly the kind of "depend on prior layer being right"
discipline the W5 architecture is supposed to enforce. Phase 6 was
listed in the roadmap AFTER Phase 5.7 for a reason. The roadmap was
right; the temptation to "just promote forest textures and see what
happens" was the wrong impulse. Documenting the pause so future me
(or future devs) understand why the catalog has a forest biome
already authored but the demo only renders alpine.

## Files left in this state

| File | State |
|---|---|
| `engine/worlds/walking_demo/materials/biome_forest/**` | Promoted; not rendered |
| `engine/worlds/walking_demo/material_variants.json` | Extended to 6 slots; renderer happily binds all 24 layers, but per-fragment selection still uses only the slot-band weights (no biome weighting), so forest siblings will activate anywhere alpine's bands are satisfied. **Visible bug if walking_demo is launched today**: forest textures may bleed onto alpine territory. |
| `engine/worlds/walking_demo/biome_catalog.json` | Both biomes present with auto_biome_rules; loader ignores auto_biome_rules today (no consumer) |

**To revert** if the bleed-bug visible in walking_demo is unwanted:
either (a) remove the forest entries from `material_variants.json`
(leave the texture files on disk for 5.7.b to consume later), or
(b) ship 5.7.b sooner. Recommend (b) — the textures cost nothing on
disk and 5.7.b is the right next sprint anyway.

## Audit / roadmap impact

- Phase 6 row in ROADMAP stays "pending"; updated note: "test
  fixture landed 2026-05-17, render gated on 5.7.b"
- Phase 5.7 row promoted from "pending" to "🚧 in progress (5.7.a
  starting)"

## Doc cap status

~110 lines (under 350 cap).
