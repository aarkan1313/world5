# Contributing to W5

> Quick pointer doc. The full lifecycle is in
> [specs/02_CONTRIBUTING_LIFECYCLE.md](specs/02_CONTRIBUTING_LIFECYCLE.md).

## TL;DR

1. **No code without a reviewed spec.** Specs live in `specs/`. If
   the system isn't spec'd, write the spec first.
2. **Follow the spec → plan → build-note → state-update cycle.** See
   spec 02 for details.
3. **Specs evolve via revision history.** Don't rewrite past entries;
   add a new line dated.
4. **STATE.md and per-tier state files match reality, not plans.** If
   code says X and STATE says Y, code wins; update STATE.
5. **Build-notes are append-only.** Write once per shipped piece of
   work; never edit later.

## Where things go

| What | Where |
|---|---|
| New system spec | `docs/specs/NN_SYSTEM_NAME.md` |
| Implementation plan for a spec | `docs/plans/NN_SYSTEM_PLAN.md` |
| Build-note for shipped work | `docs/build-notes/NN_SYSTEM_BUILD_NOTES_YYYY_MM_DD.md` |
| Current state | `docs/STATE.md` (index) + `docs/state/state_<tier>.md` |
| Next-up plan per phase | `docs/roadmap/phase_N_<name>.md` |
| Pitfalls (bug class hit, prevention recipe) | `docs/reference/pitfalls/pitfalls_<tier>.md` |
| Engine code | `engine/scripts/<system>/` |
| Pipeline code | `pipeline/<system>/` |
| Tests (Python) | `tests/` (top-level) or `pipeline/<system>/tests/` |
| Tests (GDScript) | `engine/tests/unit/` or `integration/` |

## Doc caps (spec 05)

- Top-level index files (`README.md`, `STATE.md`, `ROADMAP.md`): ≤ 200 lines
- Per-tier files (`state_<tier>.md`, `roadmap/phase_N_*.md`,
  `pitfalls_<tier>.md`): ≤ 300 lines
- Per-system specs: whatever length they need (skeleton for Tier 1+;
  comprehensive for meta + Tier 0)

If a file approaches the cap, split or migrate detail to build-notes.
Don't let the cap silently slip — that's how W4.1's STATE.md hit 845
lines.

## Pillars (spec 03)

When stuck on a technical or scope decision, the pillar order is the
tiebreaker:
1. Quality / visual fidelity
2. Performance (engine reserves 8 ms of 16.6 ms; see X_FRAME_BUDGET)
3. Architecturally correct
4. Time NOT a constraint

## Cross-spec contracts to remember

- **Frame budget**: every render-touching spec's quality bar references
  X_FRAME_BUDGET.md and quotes the authorized allocation
- **GPU/CPU compliance**: every GPU-touching spec's quality bar
  references spec 08a (GpuJob, GpuResourceTracker)
- **ChangeBroadcast schemas**: every spec that publishes a new source
  string adds metadata schema to spec 11
- **Audio tags**: every spec that emits tags adds the list to spec 34's
  canonical registry
- **Logging**: every spec declares its canonical `system_name` (≤ 15
  chars; spec 16) and lists emitted log events in Discoverability

## Lifecycle stages (spec 02)

```
IDEA → SPEC → REVIEW → PLAN → IMPLEMENT → BUILD-NOTE → STATE-UPDATE → SPEC-UPDATE (shipped)
```

Each transition is a single edit:
- `Status: draft` → `Status: reviewed` when user reads + open questions
  resolved
- `Status: reviewed` → `Status: shipped` when implementation lands +
  build-note written + STATE updated

## Status of this guide

This is a pointer doc. Full lifecycle is in spec 02. If you want depth,
read [specs/02_CONTRIBUTING_LIFECYCLE.md](specs/02_CONTRIBUTING_LIFECYCLE.md).

## Doc cap status

This file: ~75 lines (under 200 cap).
