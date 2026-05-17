# Spec: Ground Variety System

> Status: draft (Phase 4 in progress)
> Tier: 1 (core)
> Depends on: 15a_RENDERER_DECISION (clipmap), 21_TERRAIN_RENDERER,
> 23_MATERIALS_PBR, 25_TEXTURE_PIPELINE
> Consumed by: terrain renderer; world contract

## Purpose

The architecture that prevents "same texture endlessly repeated"
across the world — W4.1's biggest visible failure mode. Per user
direction, this is **Tier 0 day-1 ambition**, not Tier 2 polish.

**Committed architecture** (per spec 15a section D): **Option C
(siblings + stochastic UV) as the foundation, plus Option B (detail
texture array) as a layer on top, plus Option E (multi-frequency +
macro albedo) for far-field repeat hiding.** The clipmap primitive
makes virtual texturing (A) infeasible; building-block compositor (D)
remains a Phase 7+ upgrade path if visual quality demands it.

Why this combination:
- **C (siblings + stochastic UV, Heitz-Neyret 2018)**: gives ~48
  effective variants from 4 sibling textures with zero new pipeline
  work (existing tx_* pipeline already produces sibling sets).
  Per-fragment shader cost ~0.3 ms.
- **B (detail texture array, Cyberpunk pattern)**: 10-20× multiplier
  on top of the base. Detail overlays (grunge, moss, wet, cracks) are
  tileable PBR sets, also from the existing pipeline. ~0.2 ms
  additional shader cost.
- **E (macro albedo + multi-frequency)**: low-res world-spanning
  albedo sampled at far rings breaks distance-repeat that no per-
  fragment trick can hide. W4 had part of this and it survived audit.

## Non-goals

- Per-pixel unique textures (impossible at our scale)
- Hand-authored ground textures (we generate via the texture pipeline,
  not artist-paint)
- Hero-quality "this specific 5m × 5m area is unique" textures
  (that's decoration's job, not ground)

## Architecture (committed)

### Layer 1 — Siblings + stochastic UV (per-slot foundation)

Per surface slot, the world bundle supplies 4-8 sibling PBR sets
(palette-locked, edge-matched). The shader samples 3 offset UVs per
fragment and blends them via a world-noise mask (Heitz-Neyret 2018).
~48 effective variants per slot.

- **Author cost**: existing tx_* pipeline already produces sibling sets
  from one base prompt
- **Shader cost**: ~0.3 ms per fragment at high tier (3 albedo + 3
  normal samples per slot)
- **Schema**: `surface_slots.json` lists sibling texture paths per slot

### Layer 2 — Detail texture array (cross-slot multiplier)

Per biome, the world bundle supplies a Texture2DArray of detail
overlays (grunge, moss, wet, lichen, cracks, dust). The shader
blends one or two detail layers per fragment, selected by world-noise
and slot-specific weights.

- **Author cost**: ~5-7 detail tiles per biome (one-time per biome,
  reusable across slots)
- **Shader cost**: ~0.2 ms (1-2 detail samples)
- **Schema**: `detail_array.json` per biome lists detail textures +
  per-slot blend weights

### Layer 3 — Macro albedo + multi-frequency (far-field hider)

The world bundle supplies one low-res (2048²) world-spanning macro
albedo. Far rings sample this at world-XZ to break per-page repeat
at distance. Multi-frequency blending in the fragment shader uses
two noise octaves (high-freq for grain rotation, low-freq for tint
modulation) — both cheap and pure-shader.

- **Author cost**: macro albedo baked once per world from the biome
  catalog colors
- **Shader cost**: ~0.05 ms (1 sample + 2 noise calls)
- **Schema**: `macro_albedo.png` + `macro_albedo.json` (world AABB
  mapping) at the world bundle root

### Total shader budget

~0.55 ms per fragment at high tier across all three layers, comfortably
within the 1 ms variety budget allocated in X_FRAME_BUDGET.

## Implementation phases

Phase 4 (terrain MVP, one biome):
- Layer 3 (macro albedo) — shipped; validates far-field perception
- Layer 1 (siblings + stochastic UV) — **DEFERRED to Phase 5** (see
  amendment 2026-05-17 below). Phase 4 ships the macro-albedo
  variety layer + per-fragment world-noise modulation only.

Phase 5 (texture pipeline):
- Layer 1 (siblings + stochastic UV) — lands alongside the pipeline
  that produces sibling sets
- Layer 2 (detail array) — folds in once pipeline produces detail
  overlays

Common shader primitives (Layer 3 shipped in Phase 4 via
`variety_common.gdshaderinc`):
- `w5_world_noise(uv, freq)` — shared noise primitive (shipped)
- `w5_macro_uv(world_xz, aabb)` — far-field sample (shipped)
- `w5_variety_sample_3tap(uv, world_xz, slot)` — Heitz-Neyret 3-tap
  blend (Phase 5; needs sibling-array textures from pipeline)

## Amendment 2026-05-17 (Phase 4.4 audit response)

Original spec said "Layer 1 siblings — required for first walking
demo". The Phase 4.4 spec-vs-code review (TR-SPEC-C2) flagged that
the shader infrastructure for siblings was never built. Root cause:
**Layer 1 requires sibling textures that the texture pipeline
produces — and that pipeline doesn't exist until Phase 5.** Shipping
shader code for siblings in Phase 4 without textures to bind would
be aspirational scaffolding.

**Decision**: Layer 1 ships in Phase 5 alongside the texture pipeline.
Phase 4's walking demo shows the macro-albedo + world-noise variety
only — visibly weaker than the spec'd "no obvious repeat" bar, but
honest about what the pipeline supports today. Phase 5 closes the
gap before Phase 6 (second biome).

Spec-21 walking-demo acceptance criteria for Phase 4.6 are adjusted
accordingly: "no obvious far-field repeat" (macro-albedo job) instead
of "no obvious repeat at any distance".

## Producer / consumer contract

- **Produces**: shader uniforms + texture bindings that drive
  per-fragment variety
- **Consumes**: PBR sets / detail textures / building blocks from
  texture pipeline (spec 25)

## Dependencies

- `15a_RENDERER_DECISION` (clipmap, committed)
- `21_TERRAIN_RENDERER` (consumer; MaterialPipeline module owns the shader)
- `23_MATERIALS_PBR` (material binding layer)
- `25_TEXTURE_PIPELINE` (asset producer for siblings + detail overlays
  + macro albedo)

## Quality bar

- **Visual**: walking the 2-biome demo, no obvious texture repeat
  visible at any distance — user visual review is the gate
- **Performance**: variety-driven per-fragment cost adds ≤ 1ms to
  shader budget at high tier
- **Authoring cost**: per-biome variety setup ≤ 1 session of work
  (excluding texture generation time itself)

## Discoverability

- **Entry point**: `engine/scripts/terrain/material/MaterialPipeline.gd`
  binds the variety shader uniforms; sibling + detail + macro come
  from the world bundle
- **Schema**: `surface_slots.json` (sibling list per slot),
  `detail_array.json` (per-biome detail overlays + per-slot weights),
  `macro_albedo.json` (world AABB mapping for the macro texture)
- **Validator / preflight**: world contract checks sibling count
  per slot ≥ 1; detail array indices in range; macro albedo present
  if quality_tier ≥ medium
- **Example**: `engine/worlds/walking_demo/` is the working reference
  once Phase 4 ships
- **Deterministic outputs**: yes — all selection is world-anchored
  hash (no per-frame randomness)

## Open questions (to lock during Phase 4)

- **Sibling count per slot** — default 4; measure visual quality at
  4 vs 6 vs 8 during 4.6 walking demo
- **Detail-array vs Phase 5 deferral** — decide before 4.4
  MaterialPipeline ships whether to land Layer 2 in Phase 4 or wait
  for Phase 5 texture pipeline to make authoring trivial
- **Macro albedo resolution** — 2048² default; 4096² for ultra tier?
  Calibrate in 4.5
- **Building-block compositor (option D)** — stays planned as a
  Phase 7+ upgrade if Layers 1+2+3 don't reach the visual bar

## References

- W4.1 retrospective: ground texture variety is the #1 visible gap
- WISHLIST "Stochastic ground texturing" entry (full architecture
  walkthrough)
- Heitz & Neyret 2018 "Procedural Stochastic Texturing of Tileable
  Textures" (canonical reference for option C)
- Cyberpunk 2077 / Witcher 3 detail-array pattern (option B)
- Genshin Impact + RDR2 virtual texturing (option A)

## Revision history

- 2026-05-16: initial draft (status BLOCKED pending spec 15 output)
- 2026-05-17: unblocked by spec 15a. Committed to Layers 1+2+3
  (siblings + stochastic UV / detail texture array / macro albedo);
  building-block compositor (D) deferred to Phase 7+. Shader-budget
  arithmetic added; per-layer Phase 4 vs Phase 5 split documented.
- 2026-05-17 (later): amended — Layer 1 deferred from Phase 4 to
  Phase 5 (TR-SPEC-C2 audit response). Phase 4 ships Layer 3 only.
