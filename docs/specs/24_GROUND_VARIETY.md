# Spec: Ground Variety System

> Status: draft (BLOCKED on `15a_RENDERER_DECISION.md` — variety
> architecture is renderer-primitive-dependent)
> Tier: 1 (core)
> Depends on: 15_RENDERER_RESEARCH_BRIEF (output), 21_TERRAIN_RENDERER,
> 23_MATERIALS_PBR, 25_TEXTURE_PIPELINE
> Consumed by: terrain renderer; world contract

## Purpose

The architecture that prevents "same texture endlessly repeated"
across the world — W4.1's biggest visible failure mode. Per user
direction, this is **Tier 0 day-1 ambition**, not Tier 2 polish.

Why this spec is blocked: the variety architecture is **bound up
with the renderer primitive choice (spec 15)**. Virtual texturing
eliminates repeat by construction; clipmap needs a layered solution
on top; nanite-style has its own answer. Committing to a variety
architecture before the renderer is decided risks redundant or
incompatible work.

The spec captures the candidate architectures + the decision criteria,
and resolves to a committed approach once the renderer-research
output (spec 15a) exists.

## Non-goals

- Per-pixel unique textures (impossible at our scale)
- Hand-authored ground textures (we generate via the texture pipeline,
  not artist-paint)
- Hero-quality "this specific 5m × 5m area is unique" textures
  (that's decoration's job, not ground)

## Candidate architectures (decision pending)

In rough order of visual ceiling:

### Option A — Virtual texturing (if spec 15 picks it)
Texture data streamed at sub-pixel resolution per visible fragment.
Eliminates repeat by construction. Used in Genshin Impact, RDR2.
**Free if the renderer is virtual-textured; impossible if not.**

### Option B — Detail texture array + per-fragment selection (Cyberpunk pattern)
One base PBR set per slot + N detail overlays (grunge, wet, moss,
snow, cracks) blended per-fragment via world-noise. Detail textures
are normal tileable PBR sets (no SAM segmentation needed). Each base
set becomes ~10-20× variety. Works with any renderer primitive.

### Option C — Siblings + stochastic UV (MVP-good per WISHLIST)
Per slot: 4-8 sibling variants (palette-locked + edge-matched
family). Per-fragment: 3 UV offsets sampled + blended by world-noise
(Heitz-Neyret 2018). ~48 effective variants from 4 siblings. Works
with any renderer primitive. Adds shader cost.

### Option D — Building-block compositor (AAA-target per WISHLIST)
Per slot: 5-7 single-purpose layers (base, wet, moss, lichen, cracks,
debris). Procedural composer combines layers per-tile using
world-noise inputs. Every tile mathematically unique. Requires SAM
segmentation for layer-alpha generation; significant per-biome
art-direction work. Highest visual ceiling, highest cost.

### Option E — Multi-frequency + triplanar (W4-style + extensions)
Macro albedo + detail texture + triplanar projection on steep slopes
+ multi-octave noise blending. Hides repeat at distance via mip
selection; disguises it at close via projection variation. Doesn't
eliminate repeat — manages perception. W4 had part of this (macro
albedo); extending to triplanar + multi-frequency is low-cost
addition.

## Decision criteria

When spec 15's renderer decision lands, this spec picks variety
architecture by:

1. **If virtual texturing wins renderer**: ship A (free with the
   renderer). Maybe layer E for far-field polish.
2. **If clipmap wins renderer**: ship C (siblings + stochastic UV) as
   the foundation. D (compositor) becomes a deferred-but-real upgrade
   plan; B (detail array) folds in as a "free win" addition since it
   needs minimal pipeline work.
3. **If nanite-style wins renderer**: investigate; nanite's geometry
   density potentially changes the variety calculus (more triangles
   per material sample = less texture repeat visible).

## Implementation phases (resolved post-decision)

Phase contents depend on chosen architecture. Common to all:
- Per-fragment world-noise sampling primitive (shared shader function)
- Per-region selection contract (world-anchored hash, deterministic)
- Integration with materials spec 23's MaterialBindings

## Producer / consumer contract

- **Produces**: shader uniforms + texture bindings that drive
  per-fragment variety
- **Consumes**: PBR sets / detail textures / building blocks from
  texture pipeline (spec 25)

## Dependencies

- `15_RENDERER_RESEARCH_BRIEF` output (gates architecture choice)
- `21_TERRAIN_RENDERER` (consumer)
- `23_MATERIALS_PBR` (material binding layer)
- `25_TEXTURE_PIPELINE` (asset producer)

## Quality bar

- **Visual**: walking the 2-biome demo, no obvious texture repeat
  visible at any distance — user visual review is the gate
- **Performance**: variety-driven per-fragment cost adds ≤ 1ms to
  shader budget at high tier
- **Authoring cost**: per-biome variety setup ≤ 1 session of work
  (excluding texture generation time itself)

## Discoverability

- **Entry point**: TBD once architecture decided; likely a
  `VarietyBinding` resource consumed by MaterialPipeline
- **Schema**: TBD — depends on architecture (sibling family JSON vs
  detail-array config vs compositor block library)
- **Validator / preflight**: world contract adds checks per-architecture
- **Example**: TBD; the 2-biome demo is the working reference
- **Deterministic outputs**: yes — world-anchored seeded selection
  required (no per-frame randomness)

## Open questions

- **All architecture details** — see "Candidate architectures" above.
  Decided post spec 15.
- **Detail texture authoring**: if we go B or E, the texture pipeline
  needs to generate detail overlays in addition to base PBR sets.
  Update texture pipeline spec accordingly post-decision.
- **Building-block compositor as deferred upgrade**: regardless of v1
  choice, compositor stays planned as a real Phase 6+ upgrade if v1
  ships and visual quality demands it.

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
