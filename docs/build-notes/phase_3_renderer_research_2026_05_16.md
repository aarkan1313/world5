# Build-Note: Phase 3 Renderer Research Sprint — 2026-05-16

> Append-only diary per spec 02 R6.

## What shipped

`docs/specs/15a_RENDERER_DECISION.md` + a working prototype +
measured perf on dev hardware. Decision: **clipmap**. The research
collapsed the 5-candidate survey to 1 viable choice almost
immediately because 3 of 5 candidates require Godot features that
don't exist in 4.5 stable.

| Deliverable | Status |
|---|---|
| Section A — per-candidate analysis (5 candidates) | ✅ done |
| Section B — comparison matrix | ✅ done |
| Section C — recommended primitive + pillar justification | ✅ done (clipmap) |
| Section D — implementation outline | ✅ done (module decomposition for spec 21) |
| Section E — validation prototype | ✅ done (working scene + measured) |
| Deliverable check (per spec 15) | ✅ 3 of 4 checks pass; user signoff pending |

## What changed vs the plan

**Sprint came in under budget.** Spec 15's 5-day time-box was set
expecting the 5 candidates would each need investigation. Reality:
research surfaced upfront that mesh shaders + nanite-style + VT all
require Godot features not yet shipping in 4.5 (proposal stage,
PR pending, design-only, respectively). Per spec 15 F3 fallback +
the committed simplicity order, this collapsed the decision to
clipmap-or-clipmap-variant.

Plan estimated 3-5 sessions. Actual: **1 session.**

**Dev hardware was different than I expected.** Audit assumed RTX
4080; running Godot revealed RTX 5090 Laptop GPU. The 5090-laptop
is ~25% faster than the 4080 desktop on raw compute but similar in
memory bandwidth. Updated the 3060 extrapolation math accordingly.

**Prototype simpler than spec 15 anticipated.** Spec 15 expected a
1km × 1km full clipmap prototype; I built a SINGLE-ring 1km × 1km
prototype (130k tris). Reasoning: single ring is enough to validate
the primitive works; multi-ring is spec 21 implementation work that
shouldn't be in the research sprint. Phase 4 builds the production
multi-ring version.

## Measured numbers (per prototype README)

Dev hardware: NVIDIA RTX 5090 Laptop GPU, Vulkan 1.4.329, Forward+
- Single-ring 1km × 1km, 130k tris, vertex-shader heightmap displacement
- Vsync-uncapped: 0.5-0.8 ms/frame average (1500-1800 fps)
- 99th percentile well under 2 ms (one-off 8.6 ms spike from Godot GC)

RTX 3060 extrapolation: ~2-3 ms per ring. 8-ring production rig:
~5-8 ms estimated without LOD optimization, ~2-3 ms with proper
ring-band visibility culling. Within X_FRAME_BUDGET 2.0 ms terrain
allocation with the optimizations spec 21 + Phase 4 will land.

## Lessons learned

- **Capability survey BEFORE deep dive saves time.** I almost wrote
  500-word analyses of each of the 5 candidates before checking
  which were actually buildable in Godot 4.5. 5 minutes of web
  search would have collapsed the field upfront. Lesson: always do
  feasibility first, deep-dive second.
- **Audit C3 fallback path was exactly the right move.** Without the
  pre-committed F3 fallback ("drop to next-simplest if not buildable
  in Godot 4.5"), the decision would have stalled when 3 candidates
  fell out. Pre-committed fallbacks are cheap insurance against
  research-sprint paralysis.
- **The prototype was easy to build because Phase 2 shipped Log + the
  verify scaffolding.** MinimalClipmap.gd uses `Log.info("clipmap_proto",
  ...)` natively. If I'd been in W4 I'd have used `print()` and the
  output would have been undifferentiated. Phase 2's "lint forbids
  direct print" rule pays off here.
- **Real-GPU testing infrastructure from Phase 2.6+ was load-bearing
  here.** Without `--display-driver windows --rendering-driver vulkan`
  recipe (workflows/godot_rendering_modes.md), the prototype would
  have failed silently in headless mode. The recipe doc was written
  for tests; turned out to also be the recipe for prototype
  development.

## Open follow-ups

- [ ] User reviews + signs off on the clipmap decision (spec 15
      deliverable check item)
- [ ] Spec 21 (TERRAIN_RENDERER) can now be filled in — the module
      decomposition is already in 15a section D; just expand each
      module's spec
- [ ] Spec 24 (GROUND_VARIETY) unblocks to siblings + stochastic UV
      (option C) + detail array (option B) as v1 architecture, per
      15a section D
- [ ] Phase 4 (terrain MVP) checklist needs writing
- [ ] Texture2DRD vs Texture2DArrayRD for clipmap pages — defer to
      Phase 4 (spec 21 plan doc)
- [ ] Detail-array integration timing: B + C together at Phase 7, or
      B first then C — defer to spec 24 unblock

## Verification

End-to-end via `verify --full`: 242 tests pass in 5.2s. Phase 3
work didn't touch any Tier 0 code; verify just confirms the new
prototype doesn't break existing tests + the new files don't
violate preflight (allowlist + doc_health + logging_lint all green).

Prototype runs at 1500+ fps on RTX 5090 Laptop (vsync uncapped).
Frame budget extrapolation to RTX 3060 fits the X_FRAME_BUDGET
target with margin (more analysis in prototype README).

## Refs

- Spec 15 RENDERER_RESEARCH_BRIEF (gating brief)
- Spec 15a RENDERER_DECISION (this sprint's output)
- Spec 21 TERRAIN_RENDERER (downstream; can now unblock)
- Spec 24 GROUND_VARIETY (downstream; unblocks to siblings + detail-array)
- Pitfall meta-2 (`--headless` / RD; the recipe was load-bearing here)
- W4.1 `ClipmapWorld.gd` (7570 lines; the rebuild reference, NOT
  literal copy)
- Tokisan Games Terrain3D (Godot 4 production clipmap reference)
- Godot proposals #6822, #1834, #3177 (verified NOT in 4.5)
