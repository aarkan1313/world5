# Spec: Doc Architecture

> Status: draft
> Tier: meta
> Depends on: 01_MODULE_LAYOUT, 02_CONTRIBUTING_LIFECYCLE
> Consumed by: every contributor (human or LLM)

## Purpose

W4.1's doc problem wasn't "missing docs" — it was **navigation**:
- STATE.md was 845 lines (read time ~15 min)
- ROADMAP.md was 863 lines
- PITFALLS.md was 1537 lines
- 121 markdown files total
- Dated handoffs accumulated at the docs root

A fresh contributor (human or LLM) needed 30+ min of doc-reading just
to know current state. That's the discoverability tax. W5 architects
docs from day 1 to keep that tax low.

The goal: **any reader can find any thing within 2 clicks from the
docs root.**

## Non-goals

- Auto-generated docs from code (we write docs by hand; auto-gen is
  for API surface only)
- Forcing every doc through a templating system beyond the spec
  template
- Migration tooling from W4.1 (W4.1 stays frozen)

## The architecture

### Top-level: index files

Three top-level "front door" files in `docs/`:
- **`README.md`** — what is W5, where to start, link-out to everything
- **`STATE.md`** — index of per-tier state files + one-paragraph
  current-state summary
- **`ROADMAP.md`** — index of per-tier roadmap files + one-paragraph
  current-focus summary

Strict line cap: **< 200 lines each**. If they grow longer, content
moves down into the per-tier files. The top-level files are
navigation, not narrative.

### Per-tier state files

`docs/state/`:
- `state_meta.md` — meta + cross-cutting tier
- `state_core.md` — Tier 1 core systems
- `state_world.md` — Tier 2 world systems
- `state_output.md` — Tier 3 output / packaging

Each ≤ 300 lines (discipline cap). Each lists per-system current
state: what exists, where it lives, key files, last-touched date.
Terse — not a session log.

### Per-tier roadmap files

`docs/roadmap/`:
- `roadmap_meta.md` — meta + cross-cutting work
- `roadmap_core.md` — Tier 1 core work
- `roadmap_world.md` — Tier 2 world work
- `roadmap_output.md` — Tier 3 output work

Each ≤ 300 lines. Each ranks what's next + what's done at that tier.

### Per-tier pitfalls files

`docs/reference/pitfalls/`:
- `pitfalls_core.md` — pitfalls in terrain/materials/decoration/etc.
- `pitfalls_world.md` — pitfalls in water/weather/caves/etc.
- `pitfalls_meta.md` — pitfalls in build/test/packaging
- `pitfalls_INDEX.md` — symptom→pitfall lookup table (linkout to per-tier files)

Each pitfall keeps the W4.1 shape: symptom → cause → fix → what
didn't work → diagnostic. New pitfalls go in whichever per-tier file
matches; INDEX is updated to point at it.

### Specs, plans, build-notes

Per `02_CONTRIBUTING_LIFECYCLE`:
- `docs/specs/NN_SYSTEM.md` — one spec per system (this dir)
- `docs/plans/NN_SYSTEM_PLAN.md` — implementation plans
- `docs/build-notes/NN_SYSTEM_BUILD_NOTES_YYYY_MM_DD.md` — what shipped + lessons

No per-tier split for these because they're already per-system. They
get a per-dir README.md that lists what's in there + links.

### Workflows

`docs/workflows/`:
- One file per recurring task pattern (W4.1 has ~8; W5 will have more
  as systems ship)
- `README.md` indexes them

### Reference

`docs/reference/`:
- `TOOLS.md` — one-line-per CLI tool / script (top-level index)
- `API.md` — generated public API surface of `engine/` (auto-gen,
  see Discoverability section)
- `pitfalls/` — per-tier pitfalls (above)
- `CONTRIBUTING.md` — pointer to the lifecycle spec

### Handoffs

`docs/handoffs/`:
- All dated cross-session handoff docs live here (not at docs root)
- Filename: `HANDOFF_YYYY_MM_DD_<topic>.md`
- README.md lists most recent at top

### History

`docs/historical/`:
- Tombstones for retired systems (deleted spec → optional tombstone
  pointing at last build-note)
- Closed bugs / audit trails worth remembering

## Update protocol

Per `02_CONTRIBUTING_LIFECYCLE`:
- STATE files get edited when a system ships / closes / changes contract
- ROADMAP files get re-ranked at session boundaries
- PITFALLS files get a new entry per bug class hit
- New doc? Put it in the right dir based on type. README at each
  dir level lists what's there. Update the relevant index file.

**Line caps are advisory but binding**: when a file approaches the
cap, split or migrate detail to build-notes. Don't let the cap
silently slip.

## Public API

For LLM-discoverability:
- `docs/README.md` is the human entry; `docs/SITEMAP.json` is the
  machine entry (auto-generated from the dir tree).
- `docs/SITEMAP.json` shape:
  ```json
  {
    "version": 1,
    "generated_at": "YYYY-MM-DD",
    "sections": {
      "state": ["state/state_meta.md", "state/state_core.md", ...],
      "roadmap": [...],
      "specs": [...],
      ...
    }
  }
  ```

A pipeline tool `pipeline/docs/build_sitemap.py` regenerates
SITEMAP.json by walking the dir.

## Producer / consumer contract

- **Produces**: a navigable doc tree where any reader finds anything
  in ≤ 2 clicks from README.
- **Consumes**: every system's docs (specs, state, plans, etc.)

## Dependencies

- `01_MODULE_LAYOUT` (places `docs/` at the top level)
- `02_CONTRIBUTING_LIFECYCLE` (defines the spec → plan → build-note →
  state cycle that this architecture serves)

## Quality bar

- Fresh reader (human OR LLM) can find current state of any system
  in ≤ 2 clicks from `docs/README.md`
- No single doc file exceeds 300 lines (discipline)
- `docs/SITEMAP.json` is regenerated automatically + checked into git
- Index files (`README.md`, `STATE.md`, `ROADMAP.md` at top) ≤ 200
  lines
- Per-tier files ≤ 300 lines
- LLM agents can read `SITEMAP.json` + the relevant index file +
  the relevant per-tier file to be current-state-aware in < 5 docs

## Discoverability

- **Entry point**: `docs/README.md` (human), `docs/SITEMAP.json` (LLM)
- **Schema**: SITEMAP.json carries doc-tree shape; no other formal
  schema (Markdown is the schema)
- **Validator / preflight**: `pipeline/docs/check_doc_health.py`
  fails if any file > line cap or any index points at a missing file
- **Example**: see `02_CONTRIBUTING_LIFECYCLE.md` for the spec → plan
  → build-note → state flow as an example navigation path
- **Deterministic outputs**: SITEMAP.json is deterministic from dir
  state (no random ordering)

## Open questions

- Should `docs/specs/` have its own per-tier subdirs (specs/meta/,
  specs/core/, etc.) once it grows large? Yes probably; defer until
  spec count > 20.
- Should we have a `docs/decisions/` for explicit architecture
  decision records (ADRs)? W5 has lots of decisions captured in
  specs/plans; ADR redundant. Defer.
- Auto-generated API doc tool choice (gdscript-doc-gen, or hand-roll)?
  TBD when first system needs it.

## References

- W4.1 retrospective lessons 7 + 8: doc discoverability + STATE
  over-narration. This spec is the direct response.
- W4.1 `docs/README.md` shape (good index pattern, scale to W5's
  larger system count via per-tier split)

## Revision history

- 2026-05-16: initial draft
