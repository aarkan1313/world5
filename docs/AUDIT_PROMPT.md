# W5 Outside Audit — Prompt + Instructions

> Hand this file to a fresh-context LLM (Claude / GPT / Gemini) or
> a human reviewer. It's self-contained — the auditor needs no prior
> context from W5's development.
>
> Output: a single `AUDIT_FINDINGS.md` written in W5's `docs/` tree.

## Context for the auditor

You are reviewing the **specification layer** of a new project called
**W5** (World 5). W5 is a Godot 4.5 + Python world-generation engine,
designed to be shipped as a Godot plugin and consumed by external
game projects (the first intended consumer is a 2.5D wizard game,
but the engine itself is game-agnostic).

W5 is the clean-slate successor to W4.1 — a previous iteration that
shipped a working multi-system engine through exploration but
accumulated architectural debt. The W4.1 retrospective + tech-stack
audit (at `D:/assets/world 4/docs/W4_1_RETROSPECTIVE_2026_05_16.md`
and `D:/assets/world 4/docs/TECH_STACK_AUDIT_2026_05_16.md`) document
the lessons. W5's specs are the response.

**NO CODE EXISTS for W5.** Only 45 specification documents under
`D:/assets/world 5/docs/`. Your job is to find problems with the
SPECS before they become problems in the CODE.

## Project pillars (the design tiebreaker)

In strict order:
1. **High visual quality / fidelity** — looks good (Genshin / RDR2 / Death Stranding tier)
2. **Performance + optimization** — 60fps p99 on RTX 3060/4060 target
3. **Architecturally correct** — long-term maintainable, forkable
4. **Time-to-ship is NOT a constraint** — no shortcuts for speed

When specs make tradeoffs, this order is the tiebreaker.

## Success metric

W5 is "done" when it is a **usable, exportable, swappable world
generator that's easy to adapt and tune for whatever.** Forkable into
3+ independent game projects.

## What to read

Read in this order:
1. **`docs/SYSTEM_INVENTORY.md`** — high-level map of every system in
   W5 across 5 tiers (Meta + Tier 0 cross-cutting + Tier 1 core +
   Tier 2 world + Tier 3 output)
2. **`docs/specs/03_PILLARS.md`** — the project pillars
3. **`docs/specs/00_SPEC_TEMPLATE.md`** — the shape every spec follows
4. **`docs/specs/01_MODULE_LAYOUT.md`** — the directory contract
5. **`docs/specs/02_CONTRIBUTING_LIFECYCLE.md`** — spec → plan → code lifecycle
6. **Every other spec in `docs/specs/` (04-44)** — the actual systems

Optional context (don't have to read; use if helpful):
- `D:/assets/world 4/docs/W4_1_RETROSPECTIVE_2026_05_16.md` — W4.1 lessons
- `D:/assets/world 4/docs/TECH_STACK_AUDIT_2026_05_16.md` — W4.1 system audit
- `D:/assets/world 4/docs/strategy/WISHLIST.md` — W4.1 wishlist (some items pulled into W5)

**DO NOT READ** `docs/REVIEW_BRIEF.md` until AFTER your audit. That
doc is the W5 author's own self-flagging — reading it first will
anchor your findings to theirs. Read it last to compare what you
caught vs what they already knew.

## What to look for

Broad. Find anything wrong, missing, contradictory, unrealistic, or
poorly justified. Some specific lenses worth applying:

### Technical correctness
- Do the specs accurately describe how the underlying tech (Godot 4.5,
  GDScript, Python, the named external libraries like TRELLIS / FLUX /
  StableMaterials / gltfpack / SDFGI) actually works?
- Are perf budgets realistic? (60fps p99 on RTX 3060/4060)
- Are the algorithm choices sound? (clipmap vs virtual texturing,
  SDF cave carving, Heitz-Neyret stochastic UV, Bruneton scattering,
  A* over terrain cost grid, etc.)

### Scope realism
- The estimated "no time bound, ~100-160 sessions" total — is that
  honest or optimistic?
- Per-spec estimates (e.g. foliage ~25-35 sessions, water ~10-15) —
  reasonable, optimistic, or pessimistic?
- Are there hidden dependencies that will explode the timeline?

### Cross-spec consistency
- Do specs that share contracts (e.g. biome catalog + decoration +
  foliage) actually use the same data shapes?
- Are the cross-cutting Tier 0 primitives (Job system, spatial index,
  async asset streaming, streaming budget, change broadcast, content
  addressing) correctly consumed by every Tier 1+ system that needs
  them?
- Any spec that should be subscribed to ChangeBroadcast but isn't?
  Should publish but doesn't?

### Architectural gaps
- Missing systems entirely (something the engine will need that no
  spec covers)
- Missing cross-cutting concerns (something every Tier 1+ system
  needs that no Tier 0 spec covers)
- Missing operational concerns (logging, error handling, debugging,
  profiling, dev workflow)

### Forkability + LLM-drivability
- Is the "forkable into 3 projects" claim plausible given the specs?
- Could an LLM agent author/build/ship a W5 world without
  hand-holding?
- Is the documentation discoverability sufficient (per spec 05 doc
  architecture)?

### Spec quality
- Are open questions appropriately flagged vs hidden as assumptions?
- Are non-goals explicit + appropriate?
- Is the Discoverability section in each spec meaningful or
  perfunctory?
- Do the producer/consumer contracts make sense?

### Honest critique
- Anything that smells like over-engineering, gold-plating,
  premature optimization, premature abstraction?
- Anything that smells like under-engineering, hand-waving, or
  "we'll figure it out later" in a spec that should commit?
- Any spec that's clearly the agent's own opinion masquerading as
  user direction?

## What to write

A single file: **`D:/assets/world 5/docs/AUDIT_FINDINGS.md`**.

Suggested structure (adapt as needed):

```markdown
# W5 Spec Layer Audit — Findings

> Audit performed by [your model / name] on [date].
> Read context from W5's `docs/SYSTEM_INVENTORY.md` + all 45 specs.

## Top-line assessment

One paragraph: is the spec layer fundamentally sound? What's the
highest-priority concern? What's the most-impressive aspect? Would
you bet on this engine being delivered?

## Critical findings (must address before any code)

Things that, if not fixed, will cause real downstream pain:
- [Concern + severity + which spec(s)]

## Significant findings (worth addressing)

Things that aren't critical but should be discussed:
- [Concern + which spec(s)]

## Minor findings / polish

Things the author should know but aren't blocking:
- [Concern + which spec(s)]

## Things the author got right

What's genuinely strong about this spec layer. (Not flattery —
honest highlights worth preserving.)

## What's missing

Systems, concerns, or considerations that should have been in scope
but aren't.

## What's over-scoped

Things in scope that probably shouldn't be — over-engineering,
premature commitment, or gold-plating.

## Cross-spec inconsistencies

Specific pairs of specs that contradict each other or use
incompatible contracts.

## My honest forecast

If W5 ships per these specs, how do you expect it to land? Best-case
+ realistic + worst-case scenarios.
```

## What NOT to do

- **Don't be polite.** The agent who wrote these specs explicitly
  asked for an outside audit because internal review is biased.
  Brutal honest is the value.
- **Don't suggest implementation details.** The auditor's job is
  SPEC-level review. "This spec doesn't make sense" is useful;
  "the code should use X library" is not (that's plan-doc work).
- **Don't rewrite the specs.** Flag problems; don't author solutions.
- **Don't skip systems because they look fine on first read.** The
  point of audit is to catch what looked fine.
- **Don't dump every line of every spec into your output.** Findings
  should be terse + actionable.

## Optional: compare your findings with the author's self-review

After writing `AUDIT_FINDINGS.md`, you may read `docs/REVIEW_BRIEF.md`
(the author's self-review). Add a closing section to your audit:

```markdown
## Comparison with author's self-review

Things author flagged that I also flagged:
- ...

Things author flagged that I disagree with:
- ...

Things I flagged that author didn't:
- ...
```

This calibrates the author's self-awareness.

## Permissions for the auditor

- Read everything under `D:/assets/world 5/docs/`
- Optionally read W4.1 retrospective + audit + wishlist for context
- Write a single new file: `D:/assets/world 5/docs/AUDIT_FINDINGS.md`
- Do NOT modify existing W5 docs

## Closing

Take however long you need. Quality of audit matters more than
speed. The author values brutal honesty over comfort.
