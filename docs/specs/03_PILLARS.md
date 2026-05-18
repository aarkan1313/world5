# Spec: Project Pillars

> Status: shipped (2026-05-18; meta-spec — policy in force; pillar ordering used as durable decision-making frame; cited in CLAUDE.md + every plan)
> Tier: meta
> Depends on: none
> Consumed by: every decision in W5

## Purpose

W5 has explicit pillars that act as tiebreakers when technical or scope
decisions get hard. Captured here so they're a referenceable document,
not just an unwritten assumption.

When a contributor (human or LLM) is choosing between options, the
pillars say which one wins.

## The pillars

In strict order. Later pillars only apply when earlier ones are equal.

### 1. High visual quality / fidelity

The end product must look good. "Looks good" is judged by:
- Comparison against the project reference set (AAA outdoor terrain
  benchmarks: Genshin, RDR2, Death Stranding, Decima, etc.)
- The W4.1 anchor demo as a floor (W5 should never look worse)
- User visual review on every significant rendering change

When forced to choose between "looks better" and any other concern
below, looks-better wins.

### 2. Performance + optimization

The engine must hit 60fps on the target hardware (3060 / 4060 class
GPUs). This is a hard floor, not a "best effort." Specifically:

- Frame budget: 16.6ms p99 on target hardware
- Memory budget: per-tier ceilings (defined in `engine/resources/quality_tiers.json`)
- Streaming: no hitches > 33ms during normal walk-mode movement
- Startup: full-detail world ready < 2s on target hardware

When forced to choose between "more correct" and "faster", the **faster
path wins IF it passes the visual quality gate**. Otherwise the correct
path wins.

### 3. Architecturally correct

The engine must be:
- Easy to extend (new systems plug in via documented contracts)
- Easy to fork (any consumer can take W5 and use it without W5 dev
  tooling)
- Easy to reason about (no god-files, clear module boundaries)
- Easy to test (every meaningful behavior has a test, runnable via
  `python -m world5.verify`)

When forced to choose between "ship faster" and "design right",
design-right wins.

### 4. Time-to-ship is not a constraint

There is no deadline. Sessions can run as long as the work demands.
Sprints can be re-scoped. Plans can be redone if implementation
surfaces a better approach.

The corollary: **never compromise pillar 1, 2, or 3 to save time.**
"It's good enough for now" is not a valid argument; either it's good
enough (in which case it's done), or it isn't (in which case keep
working).

## How the pillars apply

### To technical decisions

When choosing between algorithms / data structures / library choices /
architectural patterns:
1. Which option produces the highest visual fidelity? Pick it if
   feasible.
2. If multiple options tie on fidelity: pick the most performant.
3. If those tie: pick the most architecturally clean.
4. If those tie: pick whichever is fastest to ship (no pillar applies).

### To scope decisions

When choosing what to include in W5 (or a particular sprint):
1. Does it serve a system that the consumer experience demands?
   → in scope
2. Does it improve visual quality, performance, or architecture
   meaningfully? → in scope
3. Does it just add features for their own sake? → defer to a future
   wishlist

### To tradeoff decisions

When implementation surfaces a tradeoff (e.g. "this approach is 20%
faster but 5% uglier"):
- Pillar 1 wins: take the slower-but-prettier approach
- If perf gate is at risk: fix perf with a different technique, don't
  compromise fidelity

### To "should we do X this session" questions

Always: defer if rushing X would violate any pillar. The pillar
priorities are why this works — there's no schedule pressure forcing
shortcuts.

## When the pillars conflict (rare)

If pillar 1 and 2 genuinely fight each other (e.g. a visual technique
can't hit 60fps no matter how it's implemented):
- First, search for alternative techniques that satisfy both
- If no alternative: pillar 1 wins (visual fidelity), with the system
  gated to higher quality tiers (`ultra`/`cinematic` only) and a less
  demanding fallback on lower tiers
- Document the tradeoff in a build-note + PITFALLS entry

## Anti-patterns this prevents

- "Let's ship it and polish later" — pillar 4 says don't ship without
  polish. There IS no later.
- "Good enough for the demo" — pillar 1 is binary, not graded.
- "It's faster if we cut this feature" — pillar 4 says cutting features
  for time isn't allowed. Either cut for principled reasons (out of
  scope) or don't cut.
- "We'll refactor once it works" — pillar 3 says design right the first
  time. Refactor-later usually = never-refactor.

## Producer / consumer contract

- Produces: a decision-tiebreaker that every contributor can reference
- Consumed by: every decision

## Dependencies

None. Pillars are bedrock.

## Quality bar

- Every spec references these pillars explicitly in its "Quality bar"
  section
- Every plan justifies its approach against the pillars
- Every build-note flags any pillar-compromise it made (should be rare;
  if frequent, the pillars are wrong)

## Open questions

- Should there be a sub-pillar for "LLM-drivability"? W4.1 listed it as
  cross-cutting. For W5: probably yes, fold it under pillar 3
  (architecturally correct includes "agent can drive it") rather than
  separate pillar.

## References

- W4.1 CLAUDE.md project-root: "Quality ≥ Performance > anything else
  > time-to-ship"
- User statement (this session): "we should use our pillars... time no
  issue, performance, optimization, high visual quality/fidelity"

## Revision history

- 2026-05-16: initial draft
