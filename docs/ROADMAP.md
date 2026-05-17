# W5 Roadmap (Master Index)

> Phase-level plan for W5. Top-level index; per-phase checklists live
> in `roadmap/`.
>
> Per spec 05 doc architecture: this file ≤ 200 lines. Detail lives in
> per-phase files.
>
> Last updated: 2026-05-17.

## One-paragraph current focus

**Sub-phase 4.9 closed: audit C1 + C2 + S8 fixed.** Walking demo
now binds per-fragment slot selection (mid + rock textures reach the
GPU via the new BiomeCatalog → bind_all_slots → shader loop chain)
+ multi-page heightmap per ring (RingHeightArray → bind_height_array
→ shader picks correct page per fragment from world XZ → no more
outer-ring chunk seams). Built across 3 sub-phases (4.9.b, 4.9.d,
4.9.a) with 27 new tests including 3 real-GPU visual regressions.
**Phase 4.9.c (macro_albedo for walking_demo) remains deferred**
pending Phase 5.1 W4 module port. **Next**: 5.1 unblock → 5.4.b
detail overlays + sibling_blend_freq tune → 5.6 real-hardware
calibration → 5.7 erosion sprint → Phase 6 forest. See
[audit findings](AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md) for the
full punch-list and what remains.

## Phase status

| Phase | Status | Doc | Est. sessions |
|---|---|---|---|
| Phase 1 — Spec layer | ✅ done | (48 specs in `specs/`) | ~30 |
| Phase 1.5 — Audits | ✅ done | AUDIT_FINDINGS + SELF_AUDIT_FINDINGS | ~2 |
| Phase 0 — Repo setup | ✅ done | [phase_0_repo_setup.md](roadmap/phase_0_repo_setup.md) | 1 (commit `f73b4f8`) |
| Phase 2 — Foundation build (Tier 0) | ✅ done | [phase_2_foundations.md](roadmap/phase_2_foundations.md) | 1 (commits `bcb1d62` → `cb46ffc`) |
| Phase 2 audit + fix | ✅ done | SELF_AUDIT_PHASE_2_FINDINGS | 1 (commits `17fce3d` → `d6d6c94`) |
| Phase 3 — Renderer research sprint | ✅ done | [phase_3_renderer_research.md](roadmap/phase_3_renderer_research.md) + spec 15a | 1 (came in under 3-5 estimate) |
| Phase 4 — Terrain MVP (one biome) | ✅ done (4.9 closed remaining gaps) | [phase_4_terrain_mvp.md](roadmap/phase_4_terrain_mvp.md) | 6 sessions (4.1-4.6) |
| Phase 4.5 — Calibration sprint | ⚠️ shipped; 3060 perf claim still TBD (S1) — Phase 5.6 needs real hardware | [phase_4_5_calibration.md](roadmap/phase_4_5_calibration.md) | 1 session |
| Phase 4.6 — Walking demo | ✅ done (4.9 closed multi-page binding + slot selection gaps) | [phase_4_6_walking_demo.md](roadmap/phase_4_6_walking_demo.md) | 1 session |
| Phase 4.7 — Autoload rename refactor | ✅ done | [phase_4_7_autoload_rename.md](roadmap/phase_4_7_autoload_rename.md) | 1 session |
| Phase 4.8 — Local RD refactor | ✅ done | [phase_4_8_local_rd_refactor.md](roadmap/phase_4_8_local_rd_refactor.md) | 1 session |
| **Phase 4.9 — Renderer correctness (audit-driven)** | ✅ done (4.9.a + b + d shipped; 4.9.c deferred to 5.1) | [phase_4_9_close_2026_05_17.md](build-notes/phase_4_9_close_2026_05_17.md) | 1 session |
| **Phase 5 — Ground texture pipeline** | 🚧 5.5 + 5.4 shipped (4.9 closed core gaps); 5.1 held; 5.6 pending | [25_TEXTURE_PIPELINE_PLAN.md](plans/25_TEXTURE_PIPELINE_PLAN.md) | 5-10 |
| Phase 5.5 — Variety shader Layer 1+2 | ✅ done (4.9.b finished slot selection); sibling_blend_freq tune pending (C3 → 5.6) | [phase_5_5_variety_shader.md](roadmap/phase_5_5_variety_shader.md) | 1 session |
| Phase 5.4 — First biome (alpine) | ⚠️ shipped; macro_albedo (S2) + detail/ (S3) blocked on 5.1; slot selection now active | [build-notes/phase_5_4_first_biome_2026_05_17.md](build-notes/phase_5_4_first_biome_2026_05_17.md) | 1 session (incl brown-band fix) |
| Phase 5.1 — W4 module port (held) | ⏸ held; unblocks 4.9.c + 5.4.b + 5.6 | [25_TEXTURE_PIPELINE_PLAN.md](plans/25_TEXTURE_PIPELINE_PLAN.md) | 1-2 |
| Phase 5.4.b — Detail overlays + sibling_blend_freq tune | pending (depends on 5.1) | — | 3-4 |
| Phase 5.6 — Calibration on real hardware | pending | — | 1-2 |
| Phase 5.7 — Erosion sprint (ErosionKernel + KernelComposer) | pending (was unscheduled; now placed before Phase 10) | spec 19 | multi-sprint |
| Phase 6 — Second biome | pending (4.9 unblocked; awaits 5.4.b for detail completeness) | (write when starting) | 3-5 |
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

### Cross-phase kernel deliveries

`ErosionKernel` (spec 19 sprint 2) + `KernelComposer` + `DemFeatureKernel`
are scheduled as **Phase 5.7 erosion sprint** per the 2026-05-17 audit
findings. ErosionKernel must ship before Phase 10 water (Phase 10
rivers consume its `drainage_map` + `flow_direction` +
`flow_accumulation` outputs per spec 35). DemFeatureKernel can ship
later but is in the same sprint family.

## Docs-drift discipline (audit fix 2026-05-17)

The 2026-05-17 re-audit found that build notes (transactional) were
honest about deferred work while ROADMAP + STATE (aggregate) silently
glossed over the cuts. The systemic fix:

**Every phase close MUST update ROADMAP.md + STATE.md to reflect
what the BUILD NOTE says, not what the spec promised.** A phase is
not done until the roadmap row honestly describes what shipped vs
what was cut. Use ⚠️ (shipped with caveats) instead of ✅ (clean
done) when scope was deferred — and link the build note that
explains the deferral.

The spec→roadmap→state→build-note loop must close at every phase
boundary or the docs drift again.

## Doc cap status

- This file: ~165 lines (under 200 cap)
