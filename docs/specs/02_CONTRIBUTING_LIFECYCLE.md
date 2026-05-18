# Spec: Contributing Lifecycle

> Status: shipped (2026-05-18; meta-spec — policy in force; lifecycle policy enforced daily via spec status sweeps + plan-before-code)
> Tier: meta
> Depends on: 01_MODULE_LAYOUT
> Consumed by: every contributor (human or LLM)

## Purpose

W5's process commitment: **spec sheets for everything first, then build
in reasonable order.** That commitment only holds if there's an explicit
lifecycle that prevents reverting to "write code, document later." This
spec defines the lifecycle every system follows, from idea to shipped.

W4.1 had this conceptually (spec → plan → build-note → state-update)
but didn't enforce it. Some systems shipped without specs, build-notes
were partial, STATE.md became a session log instead of state. W5
enforces.

## Non-goals

- Code-review process (separate concern; covered by git workflow)
- Branching strategy (TBD in Phase 0 setup)
- Release / versioning policy (separate spec)

## The lifecycle

```
IDEA
  ↓
SPEC          (lives in docs/specs/NN_SYSTEM.md)
  ↓
REVIEW        (status: draft → reviewed)
  ↓
PLAN          (lives in docs/plans/NN_SYSTEM_PLAN.md) — when ready to build
  ↓
IMPLEMENT     (code in engine/ or pipeline/, tests in tests/ or engine/tests/)
  ↓
BUILD-NOTE    (lives in docs/build-notes/NN_SYSTEM_BUILD_NOTES_YYYY_MM_DD.md)
  ↓
STATE-UPDATE  (docs/STATE.md reflects current reality)
  ↓
SPEC-UPDATE   (spec moves from "reviewed" → "shipped"; revision history updated)
```

### Stage 1: Idea → Spec

An idea becomes a spec when it's:
1. Significant enough to be its own system (not a method on an existing class)
2. Clear enough to write the spec template's sections without too many "TBD"s
3. Going to be implemented (otherwise it stays in WISHLIST.md)

Write the spec using `00_SPEC_TEMPLATE.md` as the template. Skeleton
depth for vertical systems, comprehensive for cross-cutting primitives.
Save as `docs/specs/NN_SYSTEM_NAME.md`. Number is the next free integer.

**No code is written at this stage.** Even if it's tempting.

### Stage 2: Spec → Reviewed

A spec moves from `Status: draft` to `Status: reviewed` after:
- The user has read it
- Open questions are either resolved or accepted as "decide during plan"
- Dependencies are identified (and either exist or have their own draft
  specs)
- The non-goals section is real (not just "we'll decide later")

The transition is a single edit: change the status line. No separate
ceremony.

### Stage 3: Reviewed → Plan

When ready to actually build, the spec gets a companion plan doc at
`docs/plans/NN_SYSTEM_PLAN.md`. The plan answers:
- Which files get created/modified
- In what order (step-by-step, executable)
- What tests get written first (TDD where it fits)
- What the acceptance criteria are
- Risks and rollback if implementation surfaces a problem

The plan is reviewed (single status edit) before coding starts.

For trivial systems (single file, < 200 lines), the plan can be inline
in the spec (a "Plan" section) rather than a separate doc.

### Stage 4: Plan → Implement

Code happens. Tests get written. The plan's checklist gets checked off
as work proceeds.

If during implementation, the plan turns out to be wrong:
- Stop coding
- Update the plan to reflect the new approach
- (Optionally) update the spec if the system itself changed
- Continue coding from the new plan

This is the only way the lifecycle stays honest. "I'll fix the docs
later" is forbidden.

### Stage 5: Implement → Build-Note

When the work ships (PR merged, branch landed, or session ends), write
a build-note at `docs/build-notes/NN_SYSTEM_BUILD_NOTES_YYYY_MM_DD.md`.

The build-note is short (a few paragraphs to a page). It answers:
- What shipped (specific files, capabilities)
- What changed vs the plan (deviations and why)
- Lessons learned (anything surprising, anything pitfall-worthy)
- Open follow-ups (what we said we'd do but punted)

Build-notes are append-only; they never get edited after writing. They
form the project's session log.

### Stage 6: Build-Note → State-Update

`docs/STATE.md` gets edited to reflect the new state. This is **terse**:
"X exists, lives at Y, here are key APIs/files." Not a narrative — the
narrative lives in build-notes.

STATE.md is split **by tier**, not per-system (SA-S1.3 fix; matches
spec 05 doc architecture). `STATE.md` is the index;
`docs/state/state_meta.md`, `state_core.md`, `state_world.md`,
`state_output.md` carry per-tier state. Each ≤ 300 lines. Per-system
detail lives within the appropriate tier file. See spec 05 for the
full architecture. This prevents W4.1's "STATE.md is 845 lines"
problem.

### Stage 7: State-Update → Spec-Update

The original spec moves from `Status: reviewed` → `Status: shipped`.
The revision history gains a line: `YYYY-MM-DD: shipped`.

If implementation surfaced changes to the system's contract, the spec
gets updated to reflect what was actually built (not what was planned).
This is critical: **the spec must match reality at all times.**

## Rules

### R1: No code without a reviewed spec

Hard rule. If you find yourself writing code for a system that has no
spec or a draft spec, stop. Write/finish the spec first.

Exception: trivial bug fixes (one-line typo, restoring a deleted comment)
don't need a spec. Anything beyond that does.

### R2: No spec promotion without dependencies satisfied

A spec can't move past "reviewed" until its dependency specs are at
least "reviewed" themselves. This forces foundation-first work.

### R3: One spec per system

Don't merge specs. Don't split specs casually. Each spec corresponds to
one identifiable system in the directory structure (one subdir under
`engine/scripts/` or `pipeline/`).

If a system grows enough to need sub-specs, that's a sign it's actually
multiple systems — refactor the spec(s) accordingly.

### R4: Specs evolve via revision history

When a spec changes, the change goes in `## Revision history` with a
date. The body of the spec always reflects current intent. Old text
goes in git history (and optionally a brief note in revision history
if it's load-bearing).

### R5: Plans are throwaway; specs are durable

A plan is for one implementation session block. Once shipped, the plan's
job is done; future plans for the same system are separate docs. Specs
outlive plans by design.

### R6: Build-notes are append-only diary

Write them once. Don't edit them later. They're the historical record.

### R7: STATE matches reality, not plans

If the code says X and STATE says Y, the code wins; update STATE. If
the plan said Z but you shipped X, the build-note records Z→X and
STATE reflects X.

### R8: Specs CAN be deleted

If a system is removed from W5 (cut entirely, not just deferred), its
spec gets deleted (along with its state and any plan docs). Build-notes
stay (history). Optional: a tombstone entry in `docs/historical/`.

## Templates

- **Spec**: `docs/specs/00_SPEC_TEMPLATE.md`
- **Plan**: TBD — write after enough specs exist to know the right
  shape. Probably modeled on superpowers `writing-plans` output.
- **Build-note**: TBD — similar timing.
- **State**: each `docs/state/*.md` follows the same shape; index in
  `docs/STATE.md`.

## Producer / consumer contract

- Consumed by: every contributor.
- Produces: a consistent project history that any reader can navigate
  bottom-up (state → build-notes → plans → specs).

## Dependencies

- 01_MODULE_LAYOUT (defines where specs/plans/build-notes/state live on
  disk)

## Quality bar

- New systems always have specs before code.
- A system's spec, plan, build-note, and state docs are findable by
  searching for the system name.
- STATE.md never contains session-log narrative — only current state.
- Build-notes accumulate over time without rot (each is dated, focused
  on what shipped that session).

## Open questions

- Should we use git tags to mark spec status transitions (e.g.
  `spec-shipped/01-module-layout`)? Probably overkill. Status field
  is the source of truth.
- Should specs require explicit reviewer? In W4 the user reviewed
  implicitly. For W5 with potentially multiple agents working,
  explicit reviewer signoff might matter. Defer until we hit it.
- Should plans for trivial systems be inline in the spec, or always
  separate? Trial both, pick one.

## References

- W4.1 retrospective: lessons 7 and 8 (doc discoverability + STATE
  over-narrates) are the W4.1 failures this spec prevents.
- superpowers/writing-plans skill: the plan-doc shape can borrow from
  it.

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-self-audit (SA-S1.3). State file convention is
  per-tier (per spec 05), not per-system. Earlier text was stale.
