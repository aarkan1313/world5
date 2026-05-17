# Phase 5.4.b (partial) — Per-biome YAMLs + sibling_blend_freq tune

> Phase: 5.4.b (partial — sub-tasks .1 + .2 shipped; .3 deferred)
> Status: 🚧 partial 2026-05-17 (b.3 detail overlays pending)
> Plan: [phase_5_4_b_detail_overlays_and_tune.md](../roadmap/phase_5_4_b_detail_overlays_and_tune.md)
> Closes (partial): audit C3 + S7

## What shipped

### Sub-task 5.4.b.1 — per-biome YAMLs (audit S7) ✅

Ported `pipeline/biomes/alpine.yaml` (16 ground + 21 mid + 14 rock
candidates = 51 entries) + `pipeline/biomes/forest.yaml` (21 mid
candidates, mid-only by design — forest ground/rock are real-ortho
not AI-generated). Both parse cleanly + match the schema
`diversity.py` expects (`biome`, `prompt_prefix`, `prompt_suffix`,
`slots: <slot>: {category, candidates: [{tag, body}]}`).

Fresh devs can now run `python -m world5.textures.diversity --biome
alpine --slot detail --batch-size 8` (etc) without authoring a YAML
from scratch. Texture team's authoring loop is unblocked end-to-end
inside the W5 repo.

### Sub-task 5.4.b.2 — sibling_blend_freq per-tier (audit C3) ✅

**Problem**: `engine/shaders/terrain_clipmap.gdshader` defaulted
`sibling_blend_freq = 0.10` (10 m wavelength on 4 m tiles → same
tile reads 2-3× before noise switches sibling = visible repeat at
eye height; spec 24 Quality bar "no obvious texture repeats" NOT
met).

**Fix**:
- Added `terrain_sibling_blend_freq` per tier in
  `engine/resources/quality_tiers.json`: low 0.20, medium 0.25, high
  0.30, ultra 0.35, cinematic 0.40. Higher tiers afford finer
  noise = less visible tile repeat.
- New binder `MaterialPipeline.bind_sibling_blend_freq(mat, freq)`
  with negative-value clamp to 0.01 (a tiny positive so the shader
  doesn't freeze on a single sibling). +2 TDD tests (RED → GREEN).
- `TerrainWorld._bind_slots_with_catalog` reads `QualityTiers.get_current()
  ["terrain_sibling_blend_freq"]` (or the override) and calls the
  binder on every ring after the slot bind.

Demo currently runs default `high` tier → 0.30 blend_freq (was 0.10);
3× finer noise wavelength. Visible-quality A/B in walking demo
deferred to user-side launch (per editor-launch policy; agent
doesn't background-launch GUI).

**Launch command for visual A/B**:
```
C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe \
  --path demo demo/scenes/walking_demo.tscn
```
What to look for: walk forward 5-30 m and compare adjacent 4 m tiles.
Pre-tune they read identical 2-3 tiles in a row; post-tune the
stochastic noise switches every ~3 m (at high tier's 0.30 freq) so
the tile-to-tile repeat is broken up at eye height.

## Files added / changed

| File | Change |
|---|---|
| `pipeline/biomes/alpine.yaml` | NEW — ported from W4 (127 lines, 51 candidates) |
| `pipeline/biomes/forest.yaml` | NEW — ported from W4 (66 lines, 21 mid candidates) |
| `engine/resources/quality_tiers.json` | +1 knob `terrain_sibling_blend_freq` per tier (5 tiers) |
| `engine/scripts/terrain/material/MaterialPipeline.gd` | NEW binder `bind_sibling_blend_freq(mat, freq)` with negative-value clamp |
| `engine/scripts/terrain/TerrainWorld.gd` | `_bind_slots_with_catalog` reads per-tier knob + calls new binder on every ring |
| `engine/tests/unit/test_material_pipeline.gd` | +2 TDD tests (RED → GREEN) |
| `docs/roadmap/phase_5_4_b_detail_overlays_and_tune.md` | NEW plan doc (3 sub-tasks: YAMLs + sibling tune + detail overlays) |

## Verify status

5/5 layers green stable in 60.0s:
- pytest 143 passed
- gut headless all passed (18/18 material_pipeline tests, +2 new)
- gut_real_gpu 49 tests passed
- preflight 0 errors / 1 warning (pre-existing)
- capture all passed

## What's still pending (sub-task 5.4.b.3)

**Detail overlay authoring (audit S3)** — separate session (2-3
sessions of ComfyUI generation + review + promote). Requires:
1. `python -m world5.textures.diversity --biome alpine --slot detail
   --batch-size 8` (or extend diversity.py to handle detail authoring
   if it doesn't natively yet)
2. `python -m world5.textures.review --biome alpine` to surface
   below-A candidates
3. Promote 5-7 A-grade tiles via `promote.py` (may need a
   `--detail` mode added; current promote handles slot variants)
4. Update walking_demo `detail_array.json` with selected tiles +
   per-slot blend weights
5. Verify Layer 2 binding lights up in walking demo

**Why deferred**: ComfyUI batches are heavy (~5-20 min/candidate
depending on backend); needs author attention; doesn't block any
downstream work since Layer 2 is gracefully optional.

## What's load-bearing post-5.4.b interim

- `terrain_sibling_blend_freq` is now a per-tier contract.
  Adding new tiers must include this knob (default 0.30 if omitted
  via `.get(..., 0.30)`).
- The binder is called from `_bind_slots_with_catalog` ONLY — if a
  caller binds slots without going through the catalog path (e.g.
  future ad-hoc scene), `sibling_blend_freq` stays at the shader
  default of 0.10. Catalog path is the canonical wire-up.
- Forest YAML is mid-slot-only by design. Phase 6 (forest biome)
  needs real-ortho ground + rock from W4's _soft_composite pipeline
  carried over; AI siblings only fill the mid slot.

## Audit status post-5.4.b interim

| Audit ID | Status |
|---|---|
| C1 — chunk seams | ✅ Phase 4.9.a |
| C2 — per-fragment slot selection | ✅ Phase 4.9.b |
| **C3 — sibling_blend_freq tune** | **✅ Phase 5.4.b.2** |
| C4 — ErosionKernel + KernelComposer | ⏸ Phase 5.7 |
| S1 — 3060 perf claim | ⏸ Phase 5.6 |
| S2 — walking_demo macro_albedo missing | ✅ Phase 4.9.c |
| S3 — detail overlays empty | ⏸ Phase 5.4.b.3 (ComfyUI batches) |
| S4 — Phase 5.1 module port | ✅ Phase 5.1 |
| S5 — GPU mutex (TRELLIS) | ⏸ Pre-emptive |
| S6 — QA gates in W5 pipeline | ✅ (tx_qa.py ported) |
| **S7 — per-biome YAMLs missing** | **✅ Phase 5.4.b.1** |
| S8 — walking_demo biome_catalog | ✅ Phase 4.9.d |

## Doc cap status

~140 lines (under 350 cap).
