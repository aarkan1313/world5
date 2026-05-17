# W5 Roadmap (Master Index)

> Phase-level plan for W5. Top-level index; per-phase checklists live
> in `roadmap/`.
>
> Per spec 05 doc architecture: this file ≤ 200 lines. Detail lives in
> per-phase files.
>
> Last updated: 2026-05-16.

## One-paragraph current focus

**Phase 4 (terrain MVP) is the next sprint.** Spec 15a renderer
decision committed: **clipmap** (3 of 5 candidates eliminated by
Godot 4.5 capability survey; clipmap proven via prototype at
~0.7 ms/frame on RTX 5090 Laptop). Spec 21 (Terrain Renderer) +
spec 24 (Ground Variety) now unblock. Phase 4 builds the production
multi-ring clipmap with per-page streaming + LOD morph zones +
multi-biome material blend, validates with one biome demo.
~5-10 sessions estimated.

## Phase status

| Phase | Status | Doc | Est. sessions |
|---|---|---|---|
| Phase 1 — Spec layer | ✅ done | (47 specs in `specs/`) | ~30 |
| Phase 1.5 — Audits | ✅ done | AUDIT_FINDINGS + SELF_AUDIT_FINDINGS | ~2 |
| Phase 0 — Repo setup | ✅ done | [phase_0_repo_setup.md](roadmap/phase_0_repo_setup.md) | 1 (commit `f73b4f8`) |
| Phase 2 — Foundation build (Tier 0) | ✅ done | [phase_2_foundations.md](roadmap/phase_2_foundations.md) | 1 (commits `bcb1d62` → `cb46ffc`) |
| Phase 2 audit + fix | ✅ done | SELF_AUDIT_PHASE_2_FINDINGS | 1 (commits `17fce3d` → `d6d6c94`) |
| Phase 3 — Renderer research sprint | ✅ done | [phase_3_renderer_research.md](roadmap/phase_3_renderer_research.md) + spec 15a | 1 (came in under 3-5 estimate) |
| **Phase 4 — Terrain MVP (one biome)** | 🚧 next | (write at start) | 5-10 |
| Phase 4.5 — **Calibration sprint** | pending | (write when starting) | 2-3 |
| Phase 5 — Ground texture pipeline | pending | (write when starting) | 5-10 |
| Phase 6 — Second biome | pending | (write when starting) | 3-5 |
| Phase 7 — Decoration end-to-end | pending | (write when starting) | 5-10 |
| Phase 8 — Foliage system | pending | (write when starting) | 25-100 (see SA-S1) |
| Phase 9 — Atmosphere + lighting | pending | (write when starting) | 3-5 |
| Phase 10 — Water (all 4 phases) | pending | (write when starting) | 10-15 |
| Phase 11 — Weather | pending | (write when starting) | 3-5 |
| Phase 12 — Caves | pending | (write when starting) | 10-15 |
| Phase 13 — Runtime deformation | pending | (write when starting) | 5-8 |
| Phase 14 — Persistence + author overrides | pending | (write when starting) | 5-10 |
| Phase 15 — Bake recipes | pending | (write when starting) | 3-5 + per-recipe |
| Phase 16 — Forkability validation | pending | (write when starting) | 3-5 |
| Phase 17 — Done bar | future | (success metric review) | — |

**Total realistic estimate**: 200-400 sessions for v1 per audit
re-estimate. Pillar 4 says no deadline.

## How to use this doc

### Starting a new phase
1. Move phase row from `pending` → `🚧 in progress` in this file
2. Create `roadmap/phase_N_<short_name>.md` checklist
3. Update [STATE.md](STATE.md) "Recent activity" with one line
4. Start working through the per-phase checklist

### During a phase
- Per-phase checklist tracks granular tasks
- Mark items done as you complete them
- Add new items as plan surfaces issues (spec 02 R4: plans evolve)

### Finishing a phase
1. Write a build-note at `build-notes/phase_N_<date>.md`
2. Move phase row from `🚧 in progress` → `✅ done` in this file
3. Update [STATE.md](STATE.md) "What exists" section + per-tier state
   files
4. Promote any shipped specs from `reviewed` → `shipped`

## Phase ordering rationale

- **Phase 0 first** — no code touches without the directory contract
- **Phase 2 (Tier 0) before any vertical** — every vertical system
  depends on Job/SpatialIndex/AssetStream/etc.
- **Phase 3 (renderer research) before Phase 4 (terrain)** — primitive
  choice cascades into specs 21 + 24 + materials
- **Phase 4.5 (calibration) after Phase 4 (terrain MVP)** — first
  real measurements unlock per-tier knob calibration
- **Phase 5 (texture pipeline) before Phase 6 (second biome)** — second
  biome needs textures
- **Phase 7 (decoration) early in vertical work** — decoration is the
  largest visible richness lift after terrain
- **Phase 8 (foliage) AFTER decoration** — foliage placement uses
  shared spatial index + placement_exclusion broadcast from decoration
- **Phase 10 (water) BEFORE Phase 11 (weather)** — weather references
  water for distance-to-water climate rule
- **Phase 16 (forkability) LAST in vertical work** — validates the
  whole engine; surfaces gaps in any system

## Phase-blocking dependencies

```
Phase 0 (setup)
  ↓
Phase 2 (Tier 0)
  ↓
Phase 3 (renderer research) ──┐
  ↓                           │
Phase 4 (terrain MVP) ←───────┘
  ↓
Phase 4.5 (calibration)
  ↓
Phase 5 (texture pipeline)
  ↓
Phase 6 (second biome)
  ↓
Phase 7 (decoration) ←────────┐
  ↓                           │
Phase 8 (foliage) ────────────┤
  ↓                           │
Phase 9 (atmo + lighting)     │
  ↓                           │
Phase 10 (water) ←────────────┘ (water consumes drainage from erosion)
  ↓
Phase 11 (weather)
  ↓
Phase 12 (caves)
  ↓
Phase 13 (deformation)
  ↓
Phase 14 (persistence)
  ↓
Phase 15 (bake recipes) + Phase 16 (forkability) — can parallelize
```

## Doc cap status

- This file: ~110 lines (well under 200 cap)
