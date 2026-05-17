# W5 Documentation Index

> Front door for humans + LLMs. Any reader can find any thing in ≤ 2
> clicks from here (per spec 05 doc architecture).

## What is W5

W5 (World 5) is a **Godot 4.5 + Python world-generation engine** shipped
as a Godot plugin and consumed by external game projects (first
intended consumer: a 2.5D wizard game). Engine + pipeline; 3D-only at
runtime; full world system (water + weather + caves + foliage +
decoration + deformation + persistence + ...).

W5 is the clean-slate successor to W4.1. W4.1 stays frozen at
[`../../world 4/`](../../world%204/) as reference.

**Success metric**: usable, exportable, swappable world generator
forkable into 3+ independent game projects.

**Pillars** (strict tiebreaker order):
1. High visual quality / fidelity
2. Performance + optimization (engine reserves 8 ms of 16.6 ms p99 on
   RTX 3060/4060; consumer game gets the other 8.6 ms)
3. Architecturally correct
4. Time-to-ship NOT a constraint

## Where to start

### If you're new (human)
1. [USAGE.md](USAGE.md) — how to run / test / open the project
2. [SYSTEM_INVENTORY.md](SYSTEM_INVENTORY.md) — high-level map of all
   systems in 5 tiers
3. [specs/03_PILLARS.md](specs/03_PILLARS.md) — the decision tiebreakers
4. [STATE.md](STATE.md) — what exists right now
5. [ROADMAP.md](ROADMAP.md) — what's next

### If you're a fresh LLM agent
1. [ORCHESTRATOR_PLANNING_GUIDE.md](ORCHESTRATOR_PLANNING_GUIDE.md) —
   how to behave with this user + current project state
2. [SITEMAP.json](SITEMAP.json) — machine-readable doc tree
3. [STATE.md](STATE.md) → drill into [state/](state/) per-tier files
4. [ROADMAP.md](ROADMAP.md) → drill into [roadmap/](roadmap/) per-phase
   files

### If you're reviewing the spec layer
1. [REVIEW_BRIEF.md](REVIEW_BRIEF.md) — author self-review; post-audit
   status at top
2. [AUDIT_FINDINGS.md](AUDIT_FINDINGS.md) — outside audit (2026-05-16)
3. [SELF_AUDIT_FINDINGS.md](SELF_AUDIT_FINDINGS.md) — self-audit +
   resolution table

## Doc tree

```
docs/
├── README.md                    ← you are here
├── USAGE.md                     ← how to run / test / open (user-facing)
├── STATE.md                     ← index of per-tier state
├── ROADMAP.md                   ← index of per-phase roadmap
├── CONTRIBUTING.md              ← pointer to spec 02 lifecycle
├── SYSTEM_INVENTORY.md          ← all systems mapped by tier
├── ORCHESTRATOR_PLANNING_GUIDE.md ← fresh-agent takeover guide
├── REVIEW_BRIEF.md              ← author self-review
├── AUDIT_FINDINGS.md            ← outside audit output
├── SELF_AUDIT_FINDINGS.md       ← self-audit + resolution table
├── SITEMAP.json                 ← machine-readable doc tree
├── specs/                       ← 47 spec docs (one per system)
├── state/                       ← per-tier current state
│   ├── state_meta.md
│   ├── state_core.md            (Tier 1 systems)
│   ├── state_world.md           (Tier 2 systems)
│   └── state_output.md          (Tier 3 systems)
├── roadmap/                     ← per-phase build plans
│   ├── phase_0_repo_setup.md    ← current phase
│   └── (future phase checklists)
├── plans/                       ← per-system implementation plans
│   (created when a spec moves to plan stage)
├── build-notes/                 ← what shipped per session
│   (created after each shipped piece of work)
├── workflows/                   ← recurring task recipes
│   ├── running_tests.md         ← verify CLI + tiers
│   └── godot_rendering_modes.md ← headless vs real-GPU
├── reference/
│   ├── pitfalls/                ← per-tier pitfalls
│   │   └── pitfalls_INDEX.md
│   └── (TOOLS.md, API.md when those land)
├── handoffs/                    ← dated cross-session handoff docs
└── historical/                  ← tombstones for retired systems
```

## Project conventions

### Lifecycle (spec 02)
Every system follows: SPEC → REVIEW → PLAN → IMPLEMENT → BUILD-NOTE
→ STATE-UPDATE → SPEC-UPDATE. No code without a reviewed spec.

### Doc architecture (spec 05)
- Top-level files ≤ 200 lines (navigation, not narrative)
- Per-tier files ≤ 300 lines (discipline cap)
- Per-system specs whatever length they need (skeleton for Tier 1+;
  comprehensive for meta + Tier 0)

### Logging (spec 16)
5 levels (DEBUG/INFO/WARN/ERROR/FATAL); structured + JSON output;
no direct `print` / `push_*` outside `Log.gd`.

### Versioning (spec 17)
Semver. Every baked artifact carries version stamps. Migration scripts
for MAJOR / breaking-MINOR bumps. No exceptions.

### Frame budget (X_FRAME_BUDGET)
Engine reserves 8 ms of the 16.6 ms frame at `high` tier; consumer
game owns the other 8.6 ms. Per-system allocations are spec'd; new
systems must displace existing.

## Status (one sentence)

**Phase 1 spec layer complete + audited + fixed.** Ready for Phase 0
(repo setup). See [STATE.md](STATE.md) for current, [ROADMAP.md](ROADMAP.md)
for next.

## Reference (W4.1 context, optional reading)

W4.1's lessons informed every W5 spec:
- [`../../world 4/docs/W4_1_RETROSPECTIVE_2026_05_16.md`](../../world%204/docs/W4_1_RETROSPECTIVE_2026_05_16.md)
- [`../../world 4/docs/TECH_STACK_AUDIT_2026_05_16.md`](../../world%204/docs/TECH_STACK_AUDIT_2026_05_16.md)
- [`../../world 4/docs/reference/PITFALLS.md`](../../world%204/docs/reference/PITFALLS.md)

W4.1 patterns to copy or skip are reviewed per-system at spec-promotion
time, not pre-decided.
