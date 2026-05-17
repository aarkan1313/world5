# Spec: Frame Budget

> Status: draft
> Tier: cross-cutting (Tier 0)
> Depends on: 03_PILLARS, 10_STREAMING_BUDGET, 13_QUALITY_TIERS
> Consumed by: every system that spends GPU or CPU time per frame
> Numbered out-of-band ("X") because added post-audit; renumber on next
> spec sweep.

## Purpose

A single authority for **how the 16.6 ms target frame budget is
divided.** Per-spec budgets are derived from this table, not invented
in each spec. The audit (2026-05-16) found per-system budgets summed to
~16.1 ms with terrain + foliage geometry + decoration draws
*unbudgeted* — a structural pillar-2 risk.

This spec exists so:
1. The engine commits to a **half-frame reserve** (8 ms) so consumers
   have room for gameplay (AI, physics, scripting, UI, abilities, VFX).
2. Each rendering subsystem gets a named share of the engine's 8 ms.
3. Adding a new system requires either fitting under its share OR
   negotiating with another system's owner to redistribute.
4. The world contract preflight can verify the per-spec numbers sum to
   the budget at each tier.

## Non-goals

- Owning the **target hardware floor** (that's spec 13 + spec 03).
- Owning **memory budget** (that's spec 10 streaming budget).
- Per-system implementation budgets (e.g. "atmosphere shader has 1.0
  ms": that's atmosphere's spec; this spec authorizes the 1.0 ms).
- Profiling tooling itself (spec 06 capture-based renderer tests +
  future profiler overlay spec).

## The half-frame rule

**The W5 engine reserves at most 8.0 ms of the 16.6 ms target frame at
the `high` tier.** The remaining 8.6 ms is consumer territory:

- Gameplay scripting (combat, AI, abilities, dialog, quests)
- Physics + collision response
- Player input + camera control logic
- UI / HUD rendering + animation
- Game-specific VFX (spell effects, particle systems beyond weather)
- Consumer audio mixing
- Save/load + network (if consumer game adds it)

This is the **engine's contract with the consumer**. If a consumer game
fits in their 8.6 ms half, the combined frame lands inside 16.6 ms p99
on a 3060/4060. If a consumer's game is heavier than 8.6 ms, they pick
a lower W5 quality tier (which shrinks the engine's share further) or
target stronger hardware.

This convention matches AAA shipping engines:
- Witcher 3: ~6-9 ms reserved for world rendering on consoles
- RDR2: ~7-10 ms for world rendering
- Death Stranding: ~5-8 ms

W5's 8 ms is on the upper end because we target a richer outdoor
rendering stack than most engines reserve.

## Per-tier global budgets

| Tier | Total frame target | Engine share | Consumer share |
|---|---|---|---|
| `low` | 16.6 ms | 4.0 ms | 12.6 ms |
| `medium` | 16.6 ms | 6.0 ms | 10.6 ms |
| `high` (default) | 16.6 ms | **8.0 ms** | 8.6 ms |
| `ultra` | 16.6 ms | 10.0 ms | 6.6 ms |
| `cinematic` | 33.3 ms (30 fps) | 20.0 ms | 13.3 ms |

p99 budget is the same as target. **Peak frame budget** (allowed for
one-off events like world load, deformation, fast-travel arrival) is
33.0 ms at every tier; consumer should hide these with loading screens
or scripted moments.

`cinematic` runs at 30 fps because it's the cinematic/screenshot tier
(per spec 13); 60 fps is not a requirement there.

## Per-system allocation at `high` tier (8.0 ms engine share)

| Spec | System | Budget | Justification |
|---|---|---|---|
| 21 | Terrain renderer geometry + draws | 2.0 ms ⚠️ | Largest visible surface; nanite/clipmap-class cost. **Phase 4.5 calibration WARNING**: measured 4-6 ms on RTX 5090 Laptop under continuous-motion streaming load at 4-6 rings; extrapolated 13-25 ms on RTX 3060 (blows budget 7-12×). Streaming-throughput limited, not rasterization. quality_tiers.json terrain_rings dropped to 3/4/5/6/7 per tier (F2 conservative). Stationary-camera pure-render baseline + Texture2DRD upload pathway pending Phase 4.6 to confirm budget achievability. |
| 23+24 | Materials + ground variety shader pass | 0.8 ms | Per-pixel tile blend + macro |
| 28 | Decoration (LOD pass + MMI draws) | 0.8 ms | LOD pass + batched MMI draws; W4 measured ~0.6 ms LOD pass alone |
| 29 | Foliage (geometry + wind shader + LOD) | 0.8 ms | Geometry draws dominate; wind shader trivial |
| 30 | Atmosphere sky shader | 0.5 ms | Bruneton sky (clouds tier-gated to ultra) |
| 30b | Atmosphere volumetric clouds | **gated** | Default OFF at high; ON at ultra (1.5 ms) |
| 31 | Lighting / SDFGI | 1.2 ms | SDFGI light variant at high; full at ultra (3.0 ms) |
| 31 | Color grading post | 0.3 ms | LUT lookup; trivial |
| 35 | Water surface shader | 0.5 ms | Tiered + per-body opt-in reflection |
| 36 | Weather particles | 0.4 ms | Trimmed from 1.5 |
| 36 | Wetness/snow accumulation shader | 0.2 ms | Trimmed from 0.6 |
| 37 | Caves runtime (interior shader / cull) | 0.0 ms | Cost is in terrain + decoration; caves don't add |
| 40 | Impostors (separate draw path) | 0.2 ms | Impostors are designed-cheap; 4 tris × N instances batched |
| 41 | Roads runtime (splat mod + decals) | 0.1 ms | Trivial; splat texture lookup |
| — | Engine overhead (job tick, broadcasts) | 0.2 ms | Tier 0 cross-cutting cost; debounced publishes |
| **Total** | — | **8.0 ms** | Exactly fits engine share. New systems MUST displace existing. |

**Arithmetic verified**: 2.0 + 0.8 + 0.8 + 0.8 + 0.5 + 1.2 + 0.3 +
0.5 + 0.4 + 0.2 + 0.0 + 0.2 + 0.1 + 0.2 = **8.0 ms**. (SA-S5.9 +
SA-S5.10 fix: prior table miscounted at 8.3 and was over-budget. This
revised table sums correctly and fits the engine share without
SDFGI gating workaround.)

## Per-system allocation at `ultra` tier (10.0 ms engine share)

Adds 2.0 ms over `high`:
- SDFGI full (was 1.2, now 3.0): +1.8 ms
- Volumetric clouds on: +1.5 ms
- Water planar reflection opt-in (per body, per scene): +0.5 ms typical
- Foliage extra LOD tier: +0.2 ms

Sum: ~12.0 ms engine. Consumer share at ultra is 6.6 ms — combat-heavy
games should not run at ultra; this tier is for screenshot/exploration.

## Per-system allocation at `medium` tier (6.0 ms engine share)

Cuts from `high`:
- No atmosphere volumetric anything (sky shader only): -0 ms (was off)
- No SDFGI (baked light only): -1.2 ms
- No wetness shader (texture lookup only): -0.2 ms
- Decoration draw budget cut: -0.3 ms
- Foliage draw budget cut: -0.3 ms

Sum: ~6.3 ms. Tight; calibration sprint will tune.

## Per-system allocation at `low` tier (4.0 ms engine share)

Aggressive cuts:
- No SDFGI, no volumetric, no wetness, no planar reflection
- Decoration + foliage minimal
- Single ground texture layer (no variety blend)
- Sky = simple gradient, no scattering

Sum: ~4.0 ms. Validates W5 runs on integrated GPUs at all.

## How a new system gets budget

A spec adding a new visible system must:
1. Declare its target frame cost per tier in its "Quality bar" section
2. Reference back to this spec
3. Either (a) fit under existing engine share, or (b) propose a budget
   redistribution from another named system
4. If (b): a spec edit on the displaced system is part of the same PR

**Specs cannot self-authorize new budget.** This spec is the authority.

## Per-spec "Quality bar" budget references

Every render-touching spec's quality bar section now reads:
"≤ X.X ms per frame at `high` tier (authorized by `X_FRAME_BUDGET.md`)"

Not: "≤ X.X ms per frame on RTX 3060" (which lets each spec invent its
own number).

## What about CPU time?

The 8 ms engine share is **GPU frame time on the render thread**. CPU
work (job system, spatial index queries, broadcast dispatch, decoration
spawn/despawn) runs on the gameplay thread + WorkerThreadPool and has
its own contract via spec 10 streaming budget.

CPU rules:
- Per-frame work on gameplay thread: ≤ 2.0 ms engine share, ≤ 6.0 ms
  consumer share (60 fps headroom)
- Worker pool jobs: no per-frame budget, bound by spec 10 active_jobs
  ceiling
- Render-thread CPU: ≤ 1.0 ms (RenderingDevice setup, push constants,
  etc.)

CPU budget detail deferred to first calibration sprint (post-terrain-MVP).

## Public API

No code API; this spec is a contract. The world contract preflight
(spec 14) reads it programmatically:

```python
# pipeline/world_contract/frame_budget.py
def validate(tier: str) -> list[Violation]:
    """For each render-touching spec, parse its declared per-tier ms cost.
    Sum. Fail if sum exceeds the tier's engine share by > 5%."""
```

```json
// engine/resources/frame_budget.json (auto-derived from specs)
{
  "schema_version": 1,
  "tiers": {
    "high": {
      "total_ms": 16.6,
      "engine_share_ms": 8.0,
      "consumer_share_ms": 8.6,
      "allocations": {
        "terrain_renderer": 2.0,
        "materials_ground_variety": 0.8,
        ...
      }
    },
    ...
  }
}
```

## Producer / consumer contract

- **Produces**: the per-tier per-system budget table + the half-frame
  engine-vs-consumer split
- **Consumes**: nothing; this is bedrock alongside specs 03 + 13

## Dependencies

- `03_PILLARS` (pillar 2 perf gate)
- `10_STREAMING_BUDGET` (memory / job budget; separate from frame time)
- `13_QUALITY_TIERS` (tier names + the 5-tier structure)

## Quality bar

- Per-spec frame budgets sum to ≤ engine share at every tier (preflight
  enforced)
- Engine + consumer combined ≤ 16.6 ms p99 (validated on the demo
  project + on at least one fork)
- `frame_budget.json` always current with this spec text (CI check)
- Calibration sprint after terrain MVP re-measures every number; this
  spec gets revised with measured values
- **Phase 4.5 partial calibration (2026-05-17)**: terrain row updated
  with WARNING flag + measured numbers. Full per-system calibration
  for non-terrain rows deferred to per-vertical phases (decoration
  4.7, foliage 4.8, etc.). See
  `docs/build-notes/phase_4_5_calibration_2026_05_17.md`.

## Discoverability

- **Entry point**: this spec; `engine/resources/frame_budget.json` for
  programmatic access
- **Schema**: JSON Schema for the budget config
- **Validator / preflight**: `world5.world_contract.frame_budget`
- **Example**: every render-touching spec's quality bar cites this spec
- **Deterministic outputs**: yes — fixed table per tier

## Open questions

- **Consumer-game declared budget**: should a consumer game declare its
  own frame budget so W5 can validate the combined target? Probably
  yes; the consumer's `project.godot` plus a `world5_consumer_budget.json`
  alongside it. Defer to v0.2.
- **Per-platform calibration**: 8 ms on 3060 may = 12 ms on a 1660. Tier
  re-mapping logic. Defer to first calibration sprint.
- **CPU budget**: above is rough. First calibration sprint defines
  measured CPU budgets per system.
- **Async compute overlap**: shaders that run async-compute don't fully
  block the frame; some budget items could be "wallclock 1.5 ms,
  blocking 0.3 ms". Defer to renderer research sprint.

## References

- Audit finding C1 (2026-05-16): the trigger for this spec
- Pillar 2 (spec 03)
- AAA reference budgets (Witcher 3, RDR2, Death Stranding talks)

## Revision history

- 2026-05-16: initial draft, post-audit. Authorized by user direction
  "we have the rest of a game to contend with" (half-frame engine
  reserve at high tier)
- 2026-05-16: post-self-audit (SA-S5.9, SA-S5.10). Fixed arithmetic
  error in high-tier subtotal (was miscounted at 8.3, actually summed
  to 8.8 — over budget). Trimmed decoration 1.0→0.8, foliage 1.0→0.8,
  impostors 0.5→0.2, engine overhead 0.3→0.2. New sum verified at
  exactly 8.0. Specs 28, 29, 40, 41 quality bars updated to match.
