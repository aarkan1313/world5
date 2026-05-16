# Spec: Renderer Research Brief (Decision Sprint)

> Status: draft
> Type: research brief, NOT a system spec
> Depends on: 03_PILLARS, 01_MODULE_LAYOUT
> Output: a decision doc (`docs/specs/15a_RENDERER_DECISION.md`) that
> commits W5 to one terrain-renderer primitive
> Consumed by: the Tier 1 Terrain Renderer spec (which can't be written
> until this output exists)

## Purpose

W4.1 used a clipmap renderer. It worked. But W4.1 never benchmarked it
against alternatives; clipmap was picked because it was familiar from
the W3 era, not because it was measured-best.

W5's pillars (quality first, time no constraint) require we **survey
the options + commit to the architecturally-best terrain primitive**
before any renderer code is written. The renderer is the load-bearing
visual + perf system; getting this wrong cascades into every other
system.

This brief defines what the research sprint must do + produce. The
sprint's OUTPUT is a decision doc that lives next to this brief as
`15a_RENDERER_DECISION.md`.

## The candidates to survey

1. **Clipmap** (W4.1's pick) — nested ring meshes around camera, snap
   on camera move, morph zones between rings, async heightmap
   generation. Well-understood; W4 production code exists as
   reference.

2. **Virtual texturing** — texture-space LOD instead of geometry-space.
   Render to virtual texture space; only resident pages are sampled.
   Genshin Impact + many AAA use this. Strong fit for AAA-quality
   ground textures (matches our "ground variety is Tier 0" call).

3. **Mesh shaders / meshlets** — modern GPU primitive (RTX 30+).
   Per-meshlet culling + LOD; very efficient for dense static
   geometry. Nanite-influenced.

4. **Nanite-style virtualized geometry** — UE5 Nanite. Streams
   sub-pixel-detail meshlets, culls everything off-screen. Highest
   quality ceiling; highest implementation cost; not natively
   available in Godot 4.5.

5. **Hybrid** — clipmap for terrain heightfield + virtual texturing
   for surface materials + meshlets for hero decoration. Best-of-each;
   most complex to integrate.

## Research deliverables

The sprint produces `15a_RENDERER_DECISION.md` containing:

### A. Per-candidate analysis

For each of the 5 candidates above:
- **Architecture summary**: 1-2 paragraphs
- **Godot 4.5 fit**: which primitives does Godot expose natively? Which
  parts require shader work / extension authoring?
- **Quality ceiling**: what's the maximum visual fidelity achievable?
  Reference real games using each technique.
- **Performance**: rough budget estimates for our target hardware
  (3060/4060). Memory, draw calls, frame time.
- **Implementation cost**: rough session-count estimate to build
- **Maintenance cost**: how hard is it to add new systems (water,
  weather, deformation) on top?
- **Risk**: what could go wrong? What's untested in Godot 4.5?

### B. Comparison matrix

Single table comparing all 5 on the same axes (quality, perf, cost,
fit, risk). Used for at-a-glance comparison.

### C. Recommended primitive + justification

The decision. With pillar-by-pillar justification:
- How does this choice serve **quality first**?
- How does it serve **performance**?
- How does it serve **architecturally correct** (longevity, extension)?
- Why is it the right call even if it costs more sessions to build?

### D. Implementation outline

The high-level shape of the renderer that this decision implies.
Not a full Terrain Renderer spec (that comes next); just enough to
prove the decision is actionable.

### E. Validation prototype

A small prototype scene at `engine/examples/renderer_research_prototype/`
that proves the chosen approach can render a 1km × 1km terrain at
target tier. Not a full system; just enough to confirm the technique
works in Godot 4.5 on our target hardware.

## Out of scope for this brief

- The actual Terrain Renderer spec (comes after this decision)
- The GPU/CPU contract details (already decided at the architecture
  level in the W5 plan; renderer choice doesn't override that)
- Per-tier calibration (separate sprint, after first renderer build)
- Survey/topdown rendering for bake recipes (Tier 3 concern)

## Process

The research sprint is **time-boxed at 5 days** of focused investigation
+ prototype. If it can't conclude in 5 days, that itself is evidence
the chosen primitive is too complex; bias toward simpler options.

Output is reviewed before the Terrain Renderer spec is written. The
Terrain Renderer spec REFERENCES this decision doc as its
"Renderer primitive" answer.

## Fallback path (committed)

Per audit (2026-05-16, finding C3): the renderer sprint is a single
point of failure for spec 21 + spec 24 + transitively the whole Tier 1.
Three failure modes need fallbacks:

### Fallback F1: Sprint can't conclude in 5 days

If the 5-day box closes without a decision, the spec primitive is
**clipmap** (W4.1's proven primitive). Rationale: clipmap is the
"if all else fails" baseline because (a) we have working W4.1
production code as reference, (b) it works in Godot 4.5 today, and
(c) it's compatible with at least two ground-variety architectures
(spec 24 options C + B + E). The decision doc still gets written; it
just says "default-to-clipmap because the sprint inconclusively
explored alternatives."

### Fallback F2: Chosen prototype doesn't hit perf gate

If the validation prototype renders below 60fps on a 3060 at 1km × 1km,
the decision is invalidated. Restart the sprint with the prototype-
failed primitive **dropped from the candidate list**. If the second
sprint also fails, fall back to F1 (clipmap default).

**Candidate simplicity order** (SA-S2.8 — for F2/F3 dropdowns):
1. Clipmap (simplest; W4 proven; pure GDScript + standard shader)
2. Detail-array-augmented clipmap (clipmap + Option B variety)
3. Hybrid clipmap + VT material only (clipmap geometry, VT for
   surface texture)
4. Virtual texturing (full)
5. Mesh shaders / meshlets
6. Nanite-style virtualized geometry (most complex)

F2/F3 drop down this list one rung at a time until something fits.

### Fallback F3: Godot 4.5 support is more partial than expected

If implementing the chosen primitive requires Godot extension authoring
(C++ module) or upstream Godot patches, that's a multi-month detour
incompatible with even pillar 4's "no constraint." Drop to the
next-simplest candidate that can ship in pure GDScript + GLSL
compute. In practice: clipmap (pure GDScript + standard shader) or
detail-array-augmented clipmap.

### What clipmap-as-fallback unlocks

Choosing clipmap is not a failure — it's the known-good primitive
that W4.1 shipped. The W5 renderer-research sprint's value is **proving
we considered alternatives**, not requiring we choose a fancier one.
The audit-flagged risk is silently defaulting to clipmap without doing
the survey; the fix is doing the survey + accepting clipmap if nothing
better measurably wins.

If clipmap wins (via F1, F2, F3, or genuinely as the best primitive),
spec 24 ground variety picks **siblings + stochastic UV** as the v1
architecture with detail-array as a "free win" addition (the W4.1
WISHLIST pattern). Compositor stays as a Phase 6+ deferred upgrade.

## Deliverable check

The research sprint is "done" when:
- [ ] `15a_RENDERER_DECISION.md` exists with sections A-E
- [ ] Validation prototype renders a 1km × 1km test scene at 60fps
      on a 3060-class GPU
- [ ] User has reviewed + signed off on the decision
- [ ] No open question in the decision doc would change the
      recommendation (open implementation questions are fine; "we
      don't know which technique to pick" is not)

## Dependencies

- `03_PILLARS` (the decision lens)
- `01_MODULE_LAYOUT` (the prototype lives at `engine/examples/...`)
- Godot 4.5 (target Godot version)
- A 3060-class (or better) GPU for prototype validation

## Quality bar

- The decision doc is unambiguous about which primitive W5 commits to
- The justification cites measured numbers, not vibes
- The validation prototype actually runs and hits target perf
- A fresh reader (human or LLM) can read this brief + the decision
  doc + understand why the primitive was picked, without needing
  external context

## Discoverability

- **Entry point**: this brief + the decision doc when it exists
- **Schema**: the decision doc has fixed sections A-E
- **Validator / preflight**: the validation prototype scene; if it
  doesn't run at 60fps on a 3060, the decision is invalidated
- **Example**: the validation prototype IS the working example
- **Deterministic outputs**: the decision is a one-time call; same
  inputs (pillars + candidates + Godot 4.5 capabilities) should
  produce same decision

## Open questions

None for this brief (the brief itself is closed; the open questions
live inside the research sprint's output).

## References

- W4.1 audit: ClipmapWorld.gd at 3900 lines is the cost of having
  picked clipmap without measuring alternatives. This sprint is the
  W5 fix.
- W4.1 PHASE_0_6_NATIVE_GPU_TERRAIN_BACKEND_SPIKE — proves the
  research-sprint pattern works (that one picked GPU compute for
  terrain backend with measured justification)

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (C3). Added Fallback path: default-to-clipmap
  if sprint inconclusive (F1), perf gate fails (F2), or Godot 4.5
  support insufficient (F3). Removed renderer sprint as single point
  of failure for whole Tier 1.
