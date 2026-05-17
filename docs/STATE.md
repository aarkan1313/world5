# W5 State (Index)

> Current state of W5. Updated when systems ship / close / change
> contract. Per spec 05 doc architecture: this file is the index; per-tier
> details live in `state/*.md`.
>
> Last updated: 2026-05-17.

## One-sentence summary

**Phase 3 (renderer research sprint) shipped.** Decision:
**clipmap** per spec 15a — 3 of 5 candidates F3-eliminated by
Godot 4.5 capability survey (mesh shaders not exposed, nanite-style
design-phase only, VT requires extensions). Prototype renders
130k-tri 1km × 1km in ~0.7 ms on RTX 5090 Laptop (extrapolated
2-3 ms on RTX 3060; fits X_FRAME_BUDGET). 242 tests pass via
`verify --full`. Ready for Phase 4 (terrain MVP).

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

- Materials / decoration / foliage / atmosphere / water vertical
  code (those land in Phase 5+; terrain is the only vertical that
  exists today)
- Spec status sweep (all 48 specs still `draft`; the lifecycle move
  to `reviewed` slipped through Phases 2-4, scheduled for Phase 5
  open)
- Real RTX 3060 measurement (Phase 4.5 calibration measures on
  dev RTX 5090 Laptop; 3060 measurement deferred until hardware
  available)
- Walking demo scene (Phase 4.6)

## What's blocked

Nothing. Spec 15a (renderer decision: clipmap) shipped at Phase 3
close. Spec 21 (Terrain Renderer) + spec 24 (Ground Variety) unblocked
2026-05-17 at Phase 4.1 start; both now `draft` with committed
architecture. Implementation in progress per
[plans/21_TERRAIN_RENDERER_PLAN.md](plans/21_TERRAIN_RENDERER_PLAN.md).

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

- 2026-05-16: **Phase 3 shipped** — clipmap renderer committed in
  spec 15a; working prototype at
  `engine/examples/renderer_research_prototype/`; 130k-tri scene
  at 0.7 ms/frame on RTX 5090 Laptop. Spec 21 + spec 24 unblock.
- 2026-05-16: Phase 2 self-audit + critical fix pass — 42 findings
  documented; all 5 criticals actioned (2 real bugs fixed, 2
  refuted by measurement, 1 reclassified); pitfall meta-3 added
- 2026-05-16: **Phase 2 shipped** (`cb46ffc`) — all 13 Tier 0
  systems in code; 224 tests pass; autoloads register; preflight
  green; real-GPU layer working
- 2026-05-16: Real-GPU test infrastructure (`cbf2ada`) — RenderingDevice
  + compute shaders in tests via `--display-driver windows`
- 2026-05-16: USAGE.md + 2 workflow recipes (`be56e8c`)
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
