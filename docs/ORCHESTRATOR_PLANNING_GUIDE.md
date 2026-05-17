# W5 Orchestrator Catchup — 2026-05-17

> If you're a fresh agent picking up W5 mid-flight, read this first.
> It tells you exactly where we are, what's been decided, what's
> pending, and how to behave with the user.
>
> Last updated 2026-05-17 post-Phase-4.9-close, entering Phase 5.1.

---

## Where we are (one sentence)

**Phase 5.1 (W4 texture-pipeline module port) is the active sub-phase.**
Phases 0 through 4.9 closed. Walking demo at
`demo/scenes/walking_demo.tscn` renders displaced firn-snow alpine
terrain end-to-end on Godot 4.6.2 (multi-page heightmap binding +
per-fragment slot selection live as of Phase 4.9.a + 4.9.b last
session). Remaining audit items (macro_albedo, detail overlays,
sibling tune, calibration, QA gates, biome YAMLs) all converge on
one unlock: port the W4 `tx_*.py` modules into
`pipeline/world5/textures/`. See current sub-phase plan at
[roadmap/phase_5_1_w4_module_port.md](roadmap/phase_5_1_w4_module_port.md).

## First actions on takeover (UPDATED for post-Phase-4.9 state)

In order:
1. Read this guide (you're doing it)
2. Read `docs/STATE.md` (current state index)
3. Read `docs/ROADMAP.md` (phase status)
4. Read `docs/AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md` (THE driving
   document right now — punch-list of audit gaps + which are open)
5. Read the current sub-phase plan
   (`docs/roadmap/phase_<active>_*.md`)
6. Read the latest 1-2 build notes in `docs/build-notes/` to see
   what shipped most recently
7. Skim `~/.claude/projects/d--assets/memory/MEMORY.md` for
   cross-session user-preference + project-context memories
8. Ask the user what they want to pick up — do NOT assume

## Current state in one paragraph (post-Phase-4.9)

W5 has shipped: 48 specs (drafts; sweep deferred), all Tier 0
foundations (13 systems with autoload via plugin), full terrain
renderer (12+ modules including multi-page heightmap binding + per-
fragment slot selection), Phase 4 calibration (5090 measured;
3060 deferred), Phase 4.6 walking demo, Phase 4.7 autoload rename,
Phase 4.8 local-RD refactor, Phase 4.9 audit closure, Phase 5 entry
(spec amendments + scaffolds), Phase 5.4 first-biome (alpine
promoted; mid/rock now rendering on slopes), Phase 5.5 variety
shader (Layer 1+2 with binders + Texture2DArray loaders).
`python -m world5.verify --full` runs 5 layers green stable in
~60s (139 pytest + gut + gut_real_gpu + preflight + capture).
Currently 56 specs + 4 build notes + 5 plan docs.

## Phases that exist now (vs the original ROADMAP rewrite history)

The ROADMAP went through one major correction (2026-05-17 audit):
phases that originally claimed ✅ done were re-flagged ⚠️ when an
audit caught that they'd shipped with critical spec gaps. The
correction added sub-phases 4.9.a/b/d to close those gaps, and the
critical phases moved back to ✅ once the gaps closed. **The
"docs-drift discipline" section in ROADMAP.md is the systemic fix**:
every phase close MUST update ROADMAP + STATE to reflect what build
notes say, not what specs promised. Don't break this discipline.

## First actions on takeover

In order:
1. Read this guide (you're doing it)
2. Read `docs/STATE.md` (one-paragraph current; index into per-tier
   state files)
3. Read `docs/ROADMAP.md` (phase status; points at current phase
   checklist)
4. Open `docs/roadmap/phase_<current>_*.md` (the actual buildable
   checklist for the in-progress phase)
5. Read `docs/SYSTEM_INVENTORY.md` (high-level map of all systems)
6. Skim `docs/REVIEW_BRIEF.md` post-self-audit status section
7. Skim `docs/AUDIT_FINDINGS.md` + `docs/SELF_AUDIT_FINDINGS.md`
   resolution tables (per-spec revision history points back to
   specific audit IDs)
8. Read `docs/specs/X_FRAME_BUDGET.md` + `docs/specs/08a_GPU_CPU_CONTRACT.md`
   (the two new Tier 0 specs added post-audit)
9. Ask the user what they want to pick up — do NOT assume

## Project identity (locked)

- **W5** = Godot 4.6.2 stable mono + Python world-generation engine
  (upgraded from 4.5 in Phase 4.4 audit response)
- **Lives at** `D:/assets/world 5/` (engine + demo + pipeline + tests + docs)
- **Godot binary**: `C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe`
- **Predecessor** W4.1 at `D:/assets/world 4/` — partial reference
  source; texture-pipeline modules being ported into W5 in Phase 5.1
  (W4 working tree is 312 commits ahead of origin from parallel-chat
  work; 5 trivial diffs as of 2026-05-17)
- **Success metric**: "usable, exportable, swappable world generator
  that's easy to adapt and tune for whatever" — forkable into 3 projects
- **Time budget**: no bound; finish properly. User explicitly said
  "we will just need to fix everything we should have at this point,
  reaudit the whole project as needed" — pillar 4 still loaded
- **Pillars** (strict tiebreaker order):
  1. High visual quality / fidelity
  2. Performance + optimization (60fps p99 on RTX 3060/4060)
  3. Architecturally correct
  4. Time-to-ship NOT a constraint

## Collaboration shape (CRITICAL — read this before you touch anything)

The user has been explicit across many sessions:

- **User sets direction.** What W5 is, who it's for, scope decisions,
  what carries over.
- **Agent makes technical calls.** Algorithms, data structures, API
  shapes, file layouts. Don't ask the user to pick between technical
  options — commit + justify per pillars.
- **Discuss-first cadence for vertical systems.** For any Tier 1+
  system spec, talk through scope + carry-over + open questions WITH
  the user before writing. Don't bulk-write 4 specs in a row without
  pausing.
- **Don't push the user into yes/no fatigue.** The user has explicitly
  said "I'm not the expert, you are" multiple times. When you find
  yourself listing 4 technical options, that's a signal to commit
  instead of ask.
- **The user reads your output.** Keep specs concise enough to skim.
  Tiered depth: meta + Tier 0 cross-cutting are comprehensive
  (600-900 words); Tier 1+ vertical are skeleton (~200-400 words).
- **"You decide" / "you pick" / "whatever you think"** means: apply
  the pillars + commit. Do NOT ask back. If a call has a real
  downstream cost the user would feel (locks W5 into hard-to-undo
  path), flag it as you commit. Otherwise just commit.
- **No mvp culture.** User explicitly said "I'm not a fan of MVPs.
  Do what's right and full the first time even if it takes time."
  But also be realistic — when a system is genuinely too much for v1
  (the compositor question earlier), say so honestly and propose a
  staged path with the architectural-right answer as the destination.

## The whole document tree (post Phase 4.9)

```
D:/assets/world 5/docs/
├── SYSTEM_INVENTORY.md                          ← high-level map of all systems
├── ORCHESTRATOR_PLANNING_GUIDE.md               ← this file
├── REVIEW_BRIEF.md                              ← user self-review aid
├── AUDIT_PROMPT.md                              ← for outside auditor (spec layer)
├── AUDIT_FINDINGS.md                            ← outside audit output (spec layer, 2026-05-16)
├── SELF_AUDIT_FINDINGS.md                       ← self-audit + resolution table
├── SELF_AUDIT_PHASE_2_FINDINGS.md               ← Phase 2 audit
├── AUDIT_PHASE_0_5_2026_05_17.md                ← Phase 0-5 audit charter (2026-05-17)
├── AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md       ← THE driving doc: gap punch-list
├── README.md                                    ← docs front door
├── USAGE.md                                     ← how to run / test / open
├── STATE.md                                     ← index of per-tier state
├── ROADMAP.md                                   ← index of phase status (+ docs-drift discipline)
├── CONTRIBUTING.md                              ← pointer to spec 02 lifecycle
├── SITEMAP.json                  ← machine-readable doc tree
├── state/                                       ← per-tier state files
│   ├── state_meta.md
│   ├── state_core.md
│   ├── state_world.md
│   └── state_output.md
├── roadmap/                                     ← per-phase checklists
│   ├── phase_0_repo_setup.md
│   ├── phase_2_foundations.md
│   ├── phase_3_renderer_research.md
│   ├── phase_4_terrain_mvp.md
│   ├── phase_4_5_calibration.md
│   ├── phase_4_6_walking_demo.md
│   ├── phase_4_7_autoload_rename.md
│   ├── phase_4_8_local_rd_refactor.md
│   ├── phase_4_9_renderer_correctness.md
│   ├── phase_5_5_variety_shader.md
│   └── phase_5_1_w4_module_port.md              ← CURRENT
├── plans/                                       ← per-system implementation plans
│   ├── 21_TERRAIN_RENDERER_PLAN.md
│   ├── 25_TEXTURE_PIPELINE_PLAN.md              ← Phase 5.1 lives here §5.1
│   └── stubs/
├── build-notes/                                 ← per-session/sub-phase narrative
│   ├── phase_0_repo_setup_2026_05_16.md
│   ├── phase_2_foundations_2026_05_16.md
│   ├── phase_3_renderer_research_2026_05_16.md
│   ├── phase_4_full_session_2026_05_17.md
│   ├── phase_4_5_calibration_2026_05_17.md
│   ├── phase_4_6_walking_demo_2026_05_17.md
│   ├── phase_4_6_visual_review_2026_05_17.md
│   ├── phase_4_9_a_multi_page_height_2026_05_17.md
│   ├── phase_4_9_b_d_slot_selection_2026_05_17.md
│   ├── phase_4_9_close_2026_05_17.md
│   ├── phase_5_4_first_biome_2026_05_17.md
│   └── phase_5_5_variety_shader_2026_05_17.md
├── workflows/                                   ← user-facing recipes
├── reference/
│   └── pitfalls/
│       ├── pitfalls_INDEX.md
│       ├── pitfalls_meta.md
│       └── pitfalls_core.md                     ← Phase 4.9 brown-band trio
└── specs/
    ├── 00_SPEC_TEMPLATE.md
    ├── 01_MODULE_LAYOUT.md
    ├── 02_CONTRIBUTING_LIFECYCLE.md
    ├── 03_PILLARS.md
    ├── 04_GODOT_ROOT_ALLOWLIST.md
    ├── 05_DOC_ARCHITECTURE.md
    ├── 06_TEST_INFRASTRUCTURE.md
    ├── 07_JOB_SYSTEM.md
    ├── 08_SPATIAL_INDEX.md
    ├── 08a_GPU_CPU_CONTRACT.md         ← NEW post-audit (C6)
    ├── 09_ASYNC_ASSET_STREAMING.md
    ├── 10_STREAMING_BUDGET.md
    ├── 11_CHANGE_BROADCAST.md
    ├── 12_CONTENT_ADDRESSING.md
    ├── 13_QUALITY_TIERS.md
    ├── 14_WORLD_CONTRACT.md
    ├── 15_RENDERER_RESEARCH_BRIEF.md
    ├── 16_LOGGING_AND_ERROR_CONVENTIONS.md
    ├── 17_VERSIONING_AND_MIGRATION.md
    ├── 18_PLUGIN_INSTALL_AND_DEV_LOOP.md
    ├── 19_KERNEL_SYSTEM.md
    ├── 20_TERRAIN_BACKEND.md
    ├── 21_TERRAIN_RENDERER.md          ← BLOCKED on spec 15
    ├── 22_BIOME_CATALOG.md
    ├── 23_MATERIALS_PBR.md
    ├── 24_GROUND_VARIETY.md            ← BLOCKED on spec 15
    ├── 25_TEXTURE_PIPELINE.md
    ├── 26_TRELLIS_3D_PIPELINE.md
    ├── 27_LOD_BAKE.md
    ├── 28_DECORATION.md
    ├── 29_FOLIAGE.md
    ├── 30_ATMOSPHERE.md
    ├── 31_LIGHTING_GI.md
    ├── 32_CAMERA_VIEW.md
    ├── 33_NAV_EXPORT.md
    ├── 34_AUDIO_HOOKS.md
    ├── 35_WATER.md
    ├── 36_WEATHER.md
    ├── 37_CAVES_INTERIORS.md
    ├── 38_RUNTIME_DEFORMATION.md
    ├── 39_PERSISTENCE_AND_AUTHOR_OVERRIDES.md
    ├── 40_IMPOSTORS.md
    ├── 41_ROADS_PATHS.md
    ├── 42_BAKE_RECIPES.md              ← skeleton; recipes deferred
    ├── 43_PLUGIN_PACKAGING.md
    ├── 44_FORKABILITY_VALIDATION.md
    └── X_FRAME_BUDGET.md               ← NEW post-audit (C1); renumber on sweep
```

## What's decided (don't re-litigate)

### Identity + scope
- W5 = engine (runtime addon) + pipeline (Python content tools)
- 3D-only at runtime; 2.5D/topdown are offline bake recipes
- Full world system in scope: water + weather + caves + deformation +
  persistence + everything
- 2 high-quality biomes for the v1 demo (proves biome-to-biome)
- Animals/NPCs OUT (consumer responsibility)
- Audio HOOKS ONLY (tag manifest; no .ogg files ship)
- LLM-drivability is a property of every system (no separate spec)
- Roads IN as Tier 2
- Impostors IN as own Tier 2

### Architecture commitments
- Module layout: `engine/` + `demo/` + `pipeline/` (spec 01)
- GPU/CPU: GPU only for v1, no CPU fallback (spec 20)
- **GPU/CPU contract is a spec, not a memory entry** (spec 08a;
  five rules + `GpuJob` + `GpuResourceTracker`; post-audit C6)
- **Frame budget: engine reserves 8 ms of 16.6 ms at high tier**
  (spec X_FRAME_BUDGET); consumer game owns the other 8.6 ms.
  Per-system budgets authorized by this spec, not invented per-spec.
- Test infra: pytest + gut + capture (spec 06; tiers
  `--fastest`/`--fast`/default/`--full` post-audit)
- Job system wraps WorkerThreadPool; zero direct WTP calls (spec 07);
  publishes `active_jobs` to streaming budget
- ChangeBroadcast dispatch modes: sync/async/job (spec 11 post-audit
  S10); heavy callbacks (decoration cleanup after deformation) MUST
  use `job`
- Spec template includes Discoverability section for LLM-drivability
- Per-tier doc split with 300-line caps (spec 05)
- Logging is 5 levels with structured + JSON output mode (spec 16);
  no `print`/`push_*` outside `Log.gd` (lint enforced)
- Semver + migration scripts; per-artifact version stamps (spec 17)
- 3 plugin install methods documented; dev-loop level 3 is hot-reload
  via change broadcast (spec 18)
- Quality tier `ultra_far` renamed `cinematic` (post-audit S7)
- TRELLIS + ComfyUI GPU mutex is a spec contract via
  `pipeline/core/gpu_mutex.py` (spec 25 post-audit S12)

### Renderer-blocked decisions (RESOLVED)
- **21 Terrain Renderer** primitive: ✅ clipmap committed in spec 15a
  (Phase 3 research sprint, 2026-05-17). Prototype measured ~0.7
  ms/frame on RTX 5090 Laptop. 3060 perf TBD per Phase 5.6 calibration.
- **24 Ground Variety** architecture: ✅ Layer 1 (siblings + 3-tap
  stochastic UV) + Layer 2 (detail array) + Layer 3 (macro albedo)
  committed. Compositor (D) deferred to Phase 7+. Currently only
  Layer 1 active in walking demo; Layer 2 + 3 blocked on Phase 5.1
  module port.

### Per-system scope calls (user-set)
- **19 Kernels**: 3 in v1 (NoiseStack + Erosion + DemFeature)
- **28 Decoration**: build fresh on Tier 0; ship R1-R9+R13+R14abc+R15
  dither; defer R5+R10+R11+R12
- **29 Foliage**: full system in v1 — trunks + procedural branches +
  leaves + variation + wind + LOD across 8 phases
- **30 Atmosphere**: Bruneton scattering + volumetric clouds IN v1
- **31 Lighting**: SDFGI on high+; per-biome lighting + color grading
  IN v1
- **35 Water**: all 4 phases (lakes + rivers + coasts + underwater)
  with tiered + per-body opt-in reflection
- **36 Weather**: visual only (no gameplay hooks); climate from biome
  catalog (no separate spec)
- **37 Caves**: caves only in v1; buildings schema reserved
- **38 Deformation**: ephemeral; engine destroys assets in crater
- **39 Persistence**: author overrides only (offline); JSON per system
- **40 Impostors**: 2 crossed billboards; alpha from LOD0 mesh render
- **41 Roads**: procedural A* + hand-authored overrides
- **42 Bake recipes**: skeleton only; specific recipes deferred

## What's pending

### Immediate (active sub-phase)
- **Phase 5.1**: port W4 `tx_*.py` modules + drivers into
  `pipeline/world5/textures/`. File-copy + path-edit per
  [plan 25 §5.1](plans/25_TEXTURE_PIPELINE_PLAN.md). ~1-2 sessions.
- Source files: `D:/assets/world 4/pipeline/textures/tx_*.py` (11
  files) + `D:/assets/world 4/pipeline/diversity_*.py` +
  `build_contact_sheet.py` (4 drivers).
- W4 working tree IS dirty (parallel-chat work, 312 commits ahead of
  origin) but the dirty diffs are tiny (5 trivial lines across all
  files). Safe to port from HEAD.

### Queued (post Phase 5.1, in priority order per audit findings)
1. **Phase 4.9.c** macro_albedo for walking_demo (1 session; needs
   `tx_macro_terrain.py` ported)
2. **Phase 5.4.b** detail overlays (3-4 sessions; needs `tx_*.py`
   ported + texture team detail authoring OR self-generation)
3. **Phase 5.6** calibration on real RTX 3060 (1-2 sessions; needs
   real hardware access)
4. **Phase 5.7** erosion sprint — ErosionKernel + KernelComposer +
   DemFeatureKernel; multi-sprint; **blocks Phase 10 water**
5. **Phase 6** second biome (forest) — 3-5 sessions; texture team
   already shipped forest candidates at `D:/tmp/w5_candidates/`

### Audit punch-list status (from 2026-05-17 re-audit)
4 critical + 9 significant + 9 minor gaps found across phases 0-5.

| Status | Items |
|---|---|
| ✅ Fixed | C1 (chunk seams, Phase 4.9.a) + C2 (per-frag slots, 4.9.b) + S8 (catalog, 4.9.d) |
| 🚧 Active | All Phase 5.1 dependencies |
| ⏸ Deferred to 5.6 | C3 (sibling tune) + S1 (3060 perf) |
| ⏸ Deferred to 5.7 | C4 (ErosionKernel + KernelComposer) |
| ⏸ Blocked on 5.1 | S2, S3, S4, S5, S6, S7 |

See `AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md` for full per-item detail.

### Estimated total scope (eyes open)
**~200-400 sessions** from Phase 0 to forkability validation
(audit re-estimate, vs original ~100-160). Pillar 4 (no deadline)
is being load-tested; user direction stands. Don't propose scope
cuts unprompted.

### Outside audit history
- 2026-05-16: outside audit on spec layer (Claude Opus 4.7,
  different session). Findings: 8 critical, 15 significant, 20
  minor, plus 15 missing items. All criticals + most significants
  fixed in spec text 2026-05-16.
- 2026-05-17: phases 0-5 spec-compliance re-audit (4 parallel read-
  only subagents). Found that Phase 4 / 4.5 / 4.6 / 5.4 / 5.5 all
  shipped with critical gaps despite ✅ in ROADMAP. Led to Phase 4.9
  sub-phase + docs-drift discipline section in ROADMAP. Audit doc
  at `AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md`.
- AUDIT_FINDINGS.md (spec-layer) is the canonical original record;
  per-spec revision history points back to specific audit IDs
  (C1-C8, S1-S15, M1-M20).

## Anti-patterns (W4.1 lessons, must avoid)

- Don't build vertical features before foundations
- Don't put pipeline scratch inside the Godot project root (spec 04
  allowlist)
- Don't write god-files (spec 21 caps modules; renderer modules <
  1000 lines, composer < 500)
- Don't ship "we'll document later" (lifecycle enforced; spec 02)
- Don't bulk-write specs without user input on scope (the user
  explicitly demanded discuss-first cadence after I batch-wrote
  19/20/21)
- Don't claim ownership of W4.1 work — W5 is clean slate
- Don't try to make W4.1 forkable; W4.1 is frozen, W5 is what gets
  forked

## How to use AskUserQuestion (calibrated to this user)

DO:
- Ask when the question requires the user's direction-setting input
  (what W5 is, what's in scope, what consumer experience to optimize
  for)
- Limit to 1-3 questions per turn; user fatigue is real
- Provide 3-4 typed options with clear tradeoffs in `description`
- Include a "you pick" option for anything that's genuinely a
  technical call

DON'T:
- Ask the user to pick between technical options (you're the
  technical authority per the pillars; commit + justify)
- Ask "is this plan okay?" or "should I proceed?" — use the natural
  flow of the conversation
- Stack 4 questions in one turn when each is a separate decision

## Where I left off when context ran out (2026-05-17, post-Phase-4.9-close)

Phase 4.9 closed end-to-end last session (commit `3dd09c3`). The
audit's three criticals (C1 chunk seams, C2 slot selection, S8
catalog) are fixed. Walking demo renders displaced firn-snow alpine
with mid+rock textures lighting up matching slopes. 5/5 verify
layers green stable in 60.6s (139 pytest + 49 gut_real_gpu including
3 new visual regressions + preflight + capture).

User direction for this session: "ok lets do it then. update all
docs roadmaps whatever needs done then the orchestrator stuff and
lets compact and continue" — i.e. start Phase 5.1 W4 module port.
Doc sweep is happening before any code touches.

Important context: a parallel chat has been doing W4 cleanup work
(W4 is 312 commits ahead of origin/main locally with 5 trivial line
diffs in working tree). The Phase 5.1 port pulls from W4 HEAD as
the effective stable state.

## Files to look at when picking up

In order:
1. This file
2. `docs/STATE.md`
3. `docs/ROADMAP.md`
4. `docs/AUDIT_FINDINGS_PHASE_0_5_2026_05_17.md` (THE active driving doc)
5. `docs/roadmap/phase_5_1_w4_module_port.md` (active sub-phase plan)
6. `docs/plans/25_TEXTURE_PIPELINE_PLAN.md` §5.1 (port table + workflow)
7. Latest 1-2 `docs/build-notes/phase_*_2026_05_17.md` (most recent ship)
8. `~/.claude/projects/d--assets/memory/MEMORY.md` (cross-session memory)
9. `docs/specs/03_PILLARS.md` (the tiebreaker — quality > perf > arch > time)
10. Any spec the user mentions in their first message

## What NOT to do on takeover

- Don't break the docs-drift discipline. Every phase close MUST
  update ROADMAP + STATE to match what build notes say. Use ⚠️
  marker (not ✅) when scope was deferred; link the build note.
- Don't write code on `main` branch without a clear sub-phase
  + plan doc + TDD test first. The Phase 4 critical gaps that the
  audit caught happened partly because code shipped without explicit
  plan + test gate.
- Don't commit textures or other heavy binaries.
  `.gitignore` excludes `engine/worlds/**/materials/**/*.png` per
  user direction (2026-05-17). Author-supplied content stays out of
  git; only manifests + scaffold dirs are tracked.
- Don't skip the discuss-first cadence to "save time" on Tier 1+ specs.
- Don't make architectural changes to spec text without
  user approval (specs ripple through every consumer).
- Don't assume W4.1 patterns are correct — every one is "carry over
  candidate, review before committing" per spec 02 lifecycle.
- Don't dispatch parallel subagents that WRITE. Read-only audit
  subagents are great (and used heavily in Phase 4.9). Write-side
  parallelism causes merge conflicts on a single-author codebase.

## How to know if you're doing it right

- User pushes back occasionally → good, you're being decisive enough
  to be wrong sometimes
- User says "good" or "go for it" without comment → good, you're
  reading the room
- User asks for clarification → good, your justification was unclear;
  add it
- User says "you decide" twice in a row on the same topic → you
  asked too many technical questions; commit + move on
- User says "you're being too cautious" → match the user's tolerance
  for decisive technical calls

## Open questions in the spec layer (audit will surface more)

Flagged in `REVIEW_BRIEF.md`. Highlights:
- Is the foliage scope (~25-35 sessions) right? User committed full
  system in v1; worth re-asking post-audit.
- Is the water scope (~10-15 sessions for all 4 phases) right? Same
  question.
- Is the cave scope (~10-15 sessions) right? Same question.
- Does DemFeatureKernel actually need to ship in v1?
- Cross-spec consistency: biome catalog + decoration + foliage all
  consume same data; verify alignment in implementation.

## Revision history

- 2026-05-16: initial draft after Phase 1 (all 45 specs) closed.
- 2026-05-16: post-outside-audit + post-engine-budget reframe. Two
  new Tier 0 specs (X_FRAME_BUDGET, 08a_GPU_CPU_CONTRACT). All
  audit criticals fixed in spec text. Scope reality acknowledged
  (200-400 sessions). Engine reserves 8 ms of 16.6 ms frame at high
  tier so consumer game has 8.6 ms for gameplay.
- 2026-05-16: post-self-audit + fix pass. ~129 fixes across specs +
  top-level docs. Frame budget math corrected. ChangeBroadcast
  metadata schemas defined. Audio tag registry canonical.
  ErosionKernel drainage outputs unlock water + roads.
- 2026-05-16: Phase 0 prep. Top-level docs landed per spec 05.
- 2026-05-17: post-Phase-4.9-close major rewrite. Stale "Where we
  are = Phase 1 closed, ready for Phase 0" replaced with current
  state (Phase 5.1 active). Stale "Phase 1.5 self-audit pending"
  removed. Phases 0-4.9 closure history captured. 2026-05-17 audit
  + findings doc added to "first actions on takeover" list.
  Docs-drift discipline noted as the systemic fix from the audit.
  Godot pin updated 4.5 → 4.6.2 stable mono. New "What NOT to do"
  items: don't break docs-drift discipline; don't commit textures;
  don't write parallel subagents.
