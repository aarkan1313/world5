# W5 State (Index)

> Current state of W5. Updated when systems ship / close / change
> contract. Per spec 05 doc architecture: this file is the index; per-tier
> details live in `state/*.md`.
>
> Last updated: 2026-05-16.

## One-sentence summary

**Phase 0 (repo scaffold) shipped + pushed to GitHub.** 47 specs +
directory tree + plugin.cfg + project.godot + pipeline package +
docs scaffold live at github.com/aarkan1313/world5.git on `main`
(commit `f73b4f8`). Ready for Phase 2 foundation build.

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

- **W5 git repo** at `D:/assets/world 5/` with remote
  `github.com/aarkan1313/world5.git` on `main` (commit `f73b4f8`)
- 47 spec docs in `specs/` (all status `draft`; outside-audited + self-audited)
- 3 audit / review docs: REVIEW_BRIEF.md, AUDIT_FINDINGS.md,
  SELF_AUDIT_FINDINGS.md
- 1 system inventory: SYSTEM_INVENTORY.md
- 1 orchestrator guide: ORCHESTRATOR_PLANNING_GUIDE.md
- Doc-tree scaffold: STATE.md + ROADMAP.md + README.md +
  CONTRIBUTING.md + state/ + roadmap/ + reference/pitfalls/
- **Directory tree per spec 01**: `engine/` + `demo/` + `pipeline/` +
  `tests/` + `tools/` with all subdirs scaffolded (empty dirs marked
  with .gitkeep)
- **`engine/plugin.cfg`** + `engine/plugin.gd` (autoloads commented
  for Phase 2)
- **`engine/README.md`** + `engine/CHANGELOG.md` (Keep-a-Changelog) +
  `engine/LICENSE` placeholder
- **`demo/project.godot`** (Godot 4.5+ Forward+) + `demo/README.md`
- **`pipeline/pyproject.toml`** editable-install package + `pipeline/world5/`
  importable Python module (version 0.0.1) + `pipeline/README.md`
- **Per-machine addon junction** at `demo/addons/world5` → `engine/`
  (created via Windows Junction since user lacks Developer Mode /
  admin; junction is in .gitignore as per-machine artifact)
- `.gitignore` + `.gitattributes` + `.godotignore.template`

## What does NOT exist yet

- Any engine system code (Tier 0 primitives, vertical systems) —
  Phase 2 builds these
- Any pipeline system code beyond the `world5` package skeleton
- Any tests
- Any lint scripts (`godot_root_check`, `doc_health`, `logging_lint`)
- `python -m world5.verify` CLI
- Any build-notes (Phase 0 build-note is the FIRST one — coming next)
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

- 2026-05-16: **Phase 0 shipped + pushed to GitHub** (commit
  `f73b4f8`); repo at github.com/aarkan1313/world5.git
- 2026-05-16: self-audit + fix pass (~129 distinct fixes)
- 2026-05-16: outside audit (`AUDIT_FINDINGS.md`)
- 2026-05-16: post-audit fix pass — 2 new specs
  (X_FRAME_BUDGET, 08a_GPU_CPU_CONTRACT); ~30 spec revisions
- 2026-05-16: Phase 1 spec writing complete (45 specs initially,
  later 47 with audit additions)

## How to update this doc

When a system ships / closes / changes contract:
1. Update the appropriate `state/state_<tier>.md` file (per-system detail)
2. Update this file's "Recent activity" + "What exists" / "What does
   NOT exist" sections (one-line summary only)
3. Append a build-note to `build-notes/`

This file stays ≤ 200 lines. If it grows, content moves down into
per-tier files (per spec 05).
