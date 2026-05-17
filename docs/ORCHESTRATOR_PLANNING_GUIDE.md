# W5 Orchestrator Catchup — 2026-05-16

> If you're a fresh agent picking up W5 mid-flight, read this first.
> It tells you exactly where we are, what's been decided, what's
> pending, and how to behave with the user.
>
> Last updated 2026-05-16 post-audit-fixes + engine-budget reframe.

---

## Where we are (one sentence)

**Phase 1 spec layer is outside-audited + self-audited + fixed.**
Outside audit (`AUDIT_FINDINGS.md`) + self-audit
(`SELF_AUDIT_FINDINGS.md`) both completed. ~129 distinct fixes
applied. Frame budget arithmetic now sums correctly at 8.0 ms high
tier. ChangeBroadcast metadata schemas defined. Audio tag registry
canonical. ErosionKernel exposes drainage outputs for water + roads.
**Ready for Phase 0 repo setup** (no known blockers in spec text).

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

- **W5** = Godot 4.5 + Python world-generation engine
- **Lives at** `D:/assets/world 5/` (currently `docs/` only; no
  engine/pipeline code yet)
- **Predecessor** W4.1 at `D:/assets/world 4/` (frozen reference,
  not code to copy)
- **Success metric**: "usable, exportable, swappable world generator
  that's easy to adapt and tune for whatever" — forkable into 3 projects
- **Time budget**: no bound; finish properly
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

## The whole document tree

```
D:/assets/world 5/docs/
├── SYSTEM_INVENTORY.md           ← high-level map of all systems
├── ORCHESTRATOR_PLANNING_GUIDE.md ← this file
├── REVIEW_BRIEF.md               ← user self-review aid (post-audit updated)
├── AUDIT_PROMPT.md               ← for outside auditor
├── AUDIT_FINDINGS.md             ← outside audit output (2026-05-16)
├── SELF_AUDIT_FINDINGS.md        ← self-audit + resolution table
├── README.md                     ← docs front door (post-Phase-0-prep)
├── USAGE.md                      ← how to run / test / open (Phase 2.6+)
├── STATE.md                      ← index of per-tier state
├── ROADMAP.md                    ← index of phase status
├── CONTRIBUTING.md               ← pointer to spec 02 lifecycle
├── SITEMAP.json                  ← machine-readable doc tree
├── state/                        ← per-tier state files
│   ├── state_meta.md
│   ├── state_core.md
│   ├── state_world.md
│   └── state_output.md
├── roadmap/                      ← per-phase checklists
│   ├── phase_0_repo_setup.md
│   └── phase_2_foundations.md    ← current phase
├── workflows/                    ← user-facing recipes (Phase 2.6+)
│   ├── running_tests.md
│   └── godot_rendering_modes.md
├── reference/
│   └── pitfalls/
│       └── pitfalls_INDEX.md
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

### Renderer-blocked decisions (deferred)
- **21 Terrain Renderer** primitive choice (clipmap / virtual texturing
  / mesh-shader / nanite-style / hybrid)
- **24 Ground Variety** architecture choice (5 candidates documented)

Both unlock when spec 15 research sprint completes.

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

### Immediate (next session)
- **Self-audit pass** (re-read specs critically with audit findings
  applied, look for what the outside audit missed)
- **THEN Phase 0**: repo setup (create engine/ + demo/ + pipeline/ +
  tests/ scaffolds per spec 01; first commit)

### Workflow planned (post Phase 0)
1. Phase 2: foundation build (Tier 0 cross-cutting primitives in code,
   including new spec 08a GPU/CPU contract + spec X_FRAME_BUDGET
   validators)
2. Phase 3: renderer research sprint (spec 15; clipmap is committed
   fallback if sprint inconclusive or fails perf gate)
3. **Phase 4.5 (new): Calibration sprint** (SA-S2.1). After terrain
   MVP ships, re-measure every per-system frame budget + every tier
   knob on real RTX 3060 hardware. Revise X_FRAME_BUDGET +
   `quality_tiers.json` with measured values. Multiple specs defer to
   this sprint (10 streaming budget, 13 quality tiers, 25 texture
   pipeline 90s estimate).
4. Phases 5+ per the W5 plan

### Estimated total scope (eyes open, post-audit)
**~200-400 sessions** from Phase 0 to forkability validation
(audit re-estimate, vs original ~100-160). Driven by:
- Foliage realistic at 60-100 sessions (audit S1; not 25-35)
- Atmosphere realistic as 2-3 specs of work (Bruneton + clouds +
  TOD); current single-spec scope underestimates
- Tier 2 (water 4-phase + weather + caves + deformation + persistence +
  impostors + roads) is genuinely small-team scope

User direction (2026-05-16): **keep v1 scope as-is**; honest
acknowledgment that pillar 4 (no deadline) is being load-tested.
Don't bring up scope-cutting unprompted; the answer is "no, finish
properly."

### Outside audit history
- 2026-05-16: outside audit run by Claude Opus 4.7 (different
  session, no prior W5 context). Findings: 8 critical, 15
  significant, 20 minor, plus 15 missing items. All criticals + most
  significants + most relevant minors fixed in spec text 2026-05-16.
- AUDIT_FINDINGS.md is the canonical record; per-spec revision
  history points back to specific audit IDs (C1-C8, S1-S15, M1-M20).

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

## Where I left off when context ran out (if applicable)

Phase 1 (all 45 specs) complete. Three immediate-prior artifacts:
- `docs/SYSTEM_INVENTORY.md` — system map
- `docs/REVIEW_BRIEF.md` — user self-review aid
- `docs/AUDIT_PROMPT.md` — for fresh-LLM auditor

User said "good" to the spec layer, is about to run outside audit
with a fresh-context model. Asked for this orchestrator catchup so
the next session (or current session post-context-compact) has
clean handoff.

## Files to look at when picking up

In order:
1. This file
2. `docs/SYSTEM_INVENTORY.md`
3. `docs/REVIEW_BRIEF.md`
4. `docs/AUDIT_PROMPT.md`
5. `docs/specs/00_SPEC_TEMPLATE.md` (the shape of every spec)
6. `docs/specs/03_PILLARS.md` (the tiebreaker)
7. Any spec the user mentions in their first message
8. (If checking W4.1 context) `D:/assets/world 4/docs/W4_1_RETROSPECTIVE_2026_05_16.md`

## What NOT to do on takeover

- Don't write any engine/pipeline code yet (audit cycle must finish first)
- Don't overwrite this guide without asking (update via Edit if
  context evolved; preserve revision history)
- Don't skip the discuss-first cadence to "save time"
- Don't make architectural changes to specs 00-44 without user
  approval (they're the foundation; changing them ripples)
- Don't assume W4.1 patterns are correct — every one is "carry over
  candidate, review before committing" per spec 02 contributing
  lifecycle
- Don't make `AUDIT_FINDINGS.md` yourself — that's the outside
  auditor's job; you help process its output AFTER it exists

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
  Supersedes the earlier orchestrator guide written after spec 18.
- 2026-05-16: post-outside-audit + post-engine-budget reframe. Two
  new Tier 0 specs (X_FRAME_BUDGET, 08a_GPU_CPU_CONTRACT). All
  audit criticals fixed in spec text. Scope reality acknowledged
  (200-400 sessions). Engine reserves 8 ms of 16.6 ms frame at high
  tier so consumer game has 8.6 ms for gameplay.
- 2026-05-16: post-self-audit + fix pass. ~129 distinct fixes
  applied across all 47 specs + top-level docs. Frame budget math
  corrected (now sums to exactly 8.0 ms). ChangeBroadcast metadata
  schemas defined. Audio tag registry canonical. ErosionKernel
  drainage outputs unlock water + roads dependencies. Calibration
  sprint added as Phase 4.5. See SELF_AUDIT_FINDINGS.md for
  per-finding resolution table.
- 2026-05-16: Phase 0 prep. Top-level docs landed per spec 05
  architecture: docs/README.md, STATE.md (index) + state/state_*.md
  per-tier files, ROADMAP.md (index) + roadmap/phase_0_repo_setup.md
  granular checklist, CONTRIBUTING.md pointer, SITEMAP.json,
  reference/pitfalls/pitfalls_INDEX.md. Top-level world 5/README.md.
  Ready to execute Phase 0 (mechanical scaffolding only).
