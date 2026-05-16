# W5 State (Index)

> Current state of W5. Updated when systems ship / close / change
> contract. Per spec 05 doc architecture: this file is the index; per-tier
> details live in `state/*.md`.
>
> Last updated: 2026-05-16.

## One-sentence summary

**Phase 1 (spec layer) complete + audited + fixed.** 47 specs across 5
tiers exist. Outside audit + self-audit + fix passes done. No engine
code exists yet. Ready for Phase 0 repo setup.

## Per-tier state

- [state/state_meta.md](state/state_meta.md) — meta + Tier 0 cross-cutting
  systems (specs 00-18 + 08a + X_FRAME_BUDGET)
- [state/state_core.md](state/state_core.md) — Tier 1 core systems
  (specs 19-34)
- [state/state_world.md](state/state_world.md) — Tier 2 world systems
  (specs 35-41)
- [state/state_output.md](state/state_output.md) — Tier 3 output / packaging
  (specs 42-44)

## What exists right now

- 47 spec docs in `specs/` (all status `draft`; outside-audited + self-audited)
- 3 audit / review docs: REVIEW_BRIEF.md, AUDIT_FINDINGS.md,
  SELF_AUDIT_FINDINGS.md
- 1 system inventory: SYSTEM_INVENTORY.md
- 1 orchestrator guide: ORCHESTRATOR_PLANNING_GUIDE.md
- Doc-tree scaffold: this STATE.md + ROADMAP.md + README.md +
  CONTRIBUTING.md + state/ + roadmap/ + reference/pitfalls/

## What does NOT exist yet

- Any engine code (`engine/scripts/`, `engine/scenes/`, etc.)
- Any pipeline code (`pipeline/`)
- Any tests (`engine/tests/`, top-level `tests/`)
- The `engine/`, `demo/`, `pipeline/` directory trees themselves
- `engine/plugin.cfg`
- The addon-link mechanism between `demo/addons/world5/` and `engine/`
- Any build-notes (no shipped work yet)
- Any plans (no system has moved to plan stage yet)

## What's blocked

- **Spec 21 (Terrain Renderer)** — BLOCKED on spec 15 renderer research
  sprint output (`docs/specs/15a_RENDERER_DECISION.md`)
- **Spec 24 (Ground Variety)** — BLOCKED on same (variety architecture
  is renderer-coupled)

Both unblock when Phase 3 (renderer research sprint) completes.

## Per-spec status snapshot

All 47 specs are `Status: draft`. The user has reviewed the spec layer
(outside audit + self-audit both done) but a formal `draft → reviewed`
status sweep hasn't run yet — that happens at Phase 0 close (so the
sweep can update the file lifecycle in a single pass).

See per-tier state files for per-system detail (what each spec covers,
key open questions, where each system's W4.1 reference lives).

## Recent activity (last 5 entries)

This is a CURRENT STATE index; the narrative log lives in build-notes.
Per spec 02 R7: STATE matches reality, not plans.

- 2026-05-16 (today): self-audit + fix pass + Phase 0 prep
- 2026-05-16: outside audit (`AUDIT_FINDINGS.md`)
- 2026-05-16: post-audit fix pass — 2 new specs
  (X_FRAME_BUDGET, 08a_GPU_CPU_CONTRACT); ~30 spec revisions
- 2026-05-16: Phase 1 spec writing complete (45 specs initially,
  later 47 with audit additions)
- 2026-05-16: project kickoff, W4.1 retrospective + tech stack audit
  written

## How to update this doc

When a system ships / closes / changes contract:
1. Update the appropriate `state/state_<tier>.md` file (per-system detail)
2. Update this file's "Recent activity" + "What exists" / "What does
   NOT exist" sections (one-line summary only)
3. Append a build-note to `build-notes/`

This file stays ≤ 200 lines. If it grows, content moves down into
per-tier files (per spec 05).
