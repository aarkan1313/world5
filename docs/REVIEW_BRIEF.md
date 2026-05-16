# W5 Spec Layer — Review Brief

> Companion to the docs in `docs/specs/`. Designed for skim-review:
> the doc highlights the load-bearing decisions + agent calls + open
> questions per spec, so you can drill into anything suspect without
> reading every spec end-to-end.
>
> Written 2026-05-16, after Phase 1 (all spec writing) closed.
> Updated 2026-05-16 post-outside-audit (`AUDIT_FINDINGS.md`) +
> post-engine-budget reframe ("we have the rest of a game to contend
> with too").

## Post-self-audit status (2026-05-16, read first)

After the outside audit + self-audit + fix passes, the spec layer is
in its most-coherent shape to date. Total findings actioned: outside
audit (8C/15S/20M+15MX) + self-audit (5C/26S/40M) = ~129 distinct
fixes across all 47 specs + top-level docs.

The frame-budget spec X_FRAME_BUDGET.md now sums correctly to 8.0 ms
at the high tier (the earlier 8.3 ms claim was arithmetic-wrong).
ChangeBroadcast metadata schemas committed. Audio tag registry
canonicalized in spec 34. ErosionKernel auxiliary outputs unlock
spec 35 water + spec 41 roads. Renderer fallback path committed.

See `SELF_AUDIT_FINDINGS.md` for per-finding resolution table.

## Post-audit status

The outside audit landed (`docs/AUDIT_FINDINGS.md`, 8 critical / 15
significant / 20 minor findings). All criticals + most significants +
most minors fixed in spec text 2026-05-16. **Two new specs added**:

- **`X_FRAME_BUDGET.md`** — engine reserves 8 ms of the 16.6 ms frame
  budget (half-frame rule); the other 8.6 ms is consumer territory
  (gameplay, AI, physics, UI, abilities). Per-system frame budgets
  rebalanced from the audit-found 16.1 ms sum to a real 8.0 ms engine
  share at high tier. SDFGI light variant at high (1.2 ms), full at
  ultra. Volumetric clouds tier-gated to ultra default (was on at
  high). Per-system "X ms p99 on 3060" lines replaced with "≤ X ms at
  high tier (authorized by X_FRAME_BUDGET.md)".
- **`08a_GPU_CPU_CONTRACT.md`** — elevates W4 memory entry to a Tier 0
  spec. Five rules (no RenderingDevice from WorkerThreadPool, etc.) +
  `GpuJob` + `GpuResourceTracker`. Resolves spec 7's open question on
  GPU compute integration.

Specs touched by audit fixes (see each spec's revision history):
01, 04, 06, 07, 11, 13, 14, 15, 18, 19, 20, 22, 23, 25, 26, 28, 29,
30, 31, 33, 36, 38, 40 — plus inventory + this brief.

**Scope reality**: audit re-estimated total v1 effort at **200-400
sessions** (vs original brief's 100-160) — driven by foliage 60-100
(not 25-35), atmosphere split needing 2-3 specs of work, Tier 2 being
genuinely a small-team scope. User direction: **keep v1 scope as-is**;
honest acknowledgment that pillar 4 (no deadline) is being load-tested.

**Engine budget reframe**: 8 ms half-frame engine reserve at high tier
means downstream consumer games (the wizard game and future forks) get
8.6 ms of headroom for gameplay. This makes consumer perf feasible
without re-baselining target hardware.

## How to use this doc

Three pass options:
- **Sanity skim (~15 min)**: read this brief top to bottom. Look at
  the "load-bearing decisions" table. Flag anything that feels wrong.
- **Targeted dive (~30-60 min)**: skim, then read the specific specs
  flagged in "spots that might bite later" + any decision you flagged.
- **Full review (~2-4 hours)**: read this brief + every spec start to
  finish. Most thorough; reserve for pre-commit decisions.

After review, push back on anything off. Specs are easy to revise at
this stage; expensive once code lands.

## What's in the spec tree

```
docs/
├── SYSTEM_INVENTORY.md         (top-level map of all systems by tier)
├── ORCHESTRATOR_PLANNING_GUIDE.md  (fresh-agent takeover guide)
├── REVIEW_BRIEF.md             (this doc)
└── specs/
    ├── 00_SPEC_TEMPLATE.md
    ├── 01-18 Meta + Tier 0 cross-cutting (foundations)
    ├── 19-34 Tier 1 core systems
    ├── 35-41 Tier 2 world systems
    └── 42-44 Tier 3 output/packaging
```

## User decisions (what YOU committed to)

Big-picture direction-setting calls you made during planning. If any of
these feel wrong now, the whole spec layer downstream is affected.

| Decision | What you said |
|---|---|
| W5 identity | Both engine (runtime) + pipeline (content) |
| Primary consumer | 3D-first runtime; 2.5D/topdown are offline bake recipes (Tier 3) |
| Success metric | "Usable, exportable, swappable; easy to adapt and tune for whatever." Forkable into 3 projects |
| Time budget | No bound — finish properly |
| Reset shape | Clean slate W5; W4.1 stays frozen at `world 4/` |
| Asset inheritance | Review-driven (assets carry over if good) |
| Scope | Full world system — water + weather + caves + deformation + persistence + everything |
| Biome count target | 2 high-quality biomes to prove biome-to-biome |
| Cadence | Spec sheets for everything first, then build in reasonable order |
| Animals/NPCs | OUT (consumer responsibility) |
| Audio | HOOKS ONLY (engine ships zero audio assets) |
| LLM-drivability | Property of every system (no separate spec) |
| Roads/Paths | IN as Tier 2 |
| Impostors | IN as own Tier 2 |
| Ground textures (compositor vs simpler) | Renderer-research-dependent (blocked) |
| Foliage | Full system in v1 (trunks + procedural branches + leaves + variation + wind + LOD) |
| Atmosphere | Bruneton scattering + volumetric clouds IN v1 |
| Per-biome lighting + color grading | IN v1 |
| Water | All 4 phases (lakes + rivers + coasts + underwater) IN v1 |
| Water reflection | Tiered + per-body opt-in (user's "consumer perf headroom" framing) |
| Weather | Visual only IN v1; gameplay hooks consumer's job |
| Caves | Caves only IN v1; buildings schema reserved |
| Runtime deformation | Ephemeral + destroy-assets-in-crater |
| Persistence | Author overrides only (offline); JSON per system |
| Impostor alpha source | Render from LOD0 mesh (canonical AAA) |
| Roads generation | Full procedural A* + hand-authored overrides |
| Bake recipes v1 | Skeleton only (contract + stub; specific recipes deferred) |
| Renderer primitive | TBD via spec 15 research sprint (BLOCKED) |
| GPU/CPU contract | GPU only in v1 (no CPU fallback) |
| Quality tiers | 5 names (low/medium/high/ultra/cinematic); numbers TBD per-system. `ultra_far` renamed to `cinematic` post-audit |
| Engine frame budget | 8 ms of 16.6 ms at high tier (post-audit reframe; consumer gets 8.6 ms) |
| Spec depth | Tiered (meta+Tier 0 comprehensive; Tier 1+ skeleton) |
| Spec writing pace | One at a time, interactive |

## Agent calls (technical decisions I made — verify these)

When you said "you pick" or "whatever you think," these are the calls I
committed to per pillar. If any feel wrong, push back:

| Spec | Agent call | Rationale |
|---|---|---|
| 01 module layout | `engine/` + `demo/` + `pipeline/` split | Forces plugin discipline from commit #1 |
| 03 pillars | Time-no-constraint is the slowest priority; quality wins ties | User-given framing codified |
| 05 doc architecture | Per-tier split with 300-line cap on per-tier files | Prevents W4.1's 845-line STATE.md |
| 06 test infra | Tiered verify command (fast / default / full) | Best dev iteration loop |
| 07 job system | Wraps WTP completely; zero direct WTP calls allowed | Prevents PITFALLS #10 |
| 19 kernels | 3 kernels in v1 (NoiseStack + Erosion + DemFeature) | Astro deferred (no consumer) |
| 23 materials | Variable 1-8 slots per biome; required maps = albedo+normal+roughness | Visual quality + auth flex |
| 24 ground variety | BLOCKED stub | 5 candidate architectures all viable; renderer primitive shapes choice |
| 25 textures | Detail overlays IN v1; SAM deferred | Detail overlays useful regardless; SAM only matters for compositor |
| 27 LOD bake | 3 tiers (LOD0/1/2) + impostors handle distant separately | Cleaner separation; impostor system gets its own spec |
| 28 decoration | Build fresh on Tier 0 (not copy from W4); ship R1+R2+R3+R4+R6+R7+R8+R9+R13+R14abc+R15 dither; defer R5+R10+R11+R12 | Bug-class fresh; visible-quality sprints in v1 |
| 29 foliage | All 8 phases in v1 architecture; phased implementation order documented | Largest single Tier 1 system; ~25-35 sessions |
| 30 atmosphere | Bruneton scattering (you said clouds; I picked scattering to match) | Volumetric clouds look weird with builtin sky |
| 31 lighting | SDFGI on high+; analytical on low/medium | Pillar 2 says don't tank perf on target HW |
| 32 camera | Single 3D walk camera; iso/topdown deleted from runtime | Matches 3D-first commitment |
| 33 nav export | W4 carry-over (no decisions) | Pattern was solid |
| 34 audio hooks | Audio-tag manifest; signals on biome+zone+point sources | Per inventory hooks-only call |
| 35 water | Tiered + per-body opt-in reflection (consumer perf headroom framing) | YOUR insight made this call |
| 36 weather | Climate from biome catalog (no separate spec) | Already in spec 22; no need for new spec |
| 39 persistence | Author overrides only (offline); JSON per system | Engine ships authoring; runtime save-state is consumer |
| 42 bake recipes | Skeleton only | You said "we don't know what this looks like yet" |

## Blocked-on-renderer-research specs

Two specs explicitly BLOCKED:

- **21 Terrain Renderer** — primitive choice (clipmap vs virtual
  texturing vs nanite-style vs hybrid) is the gate. Per spec 15
  research brief.
- **24 Ground Variety** — variety architecture is renderer-primitive-
  dependent (virtual texturing eliminates repeat by construction;
  clipmap needs layered solution). 5 candidate architectures documented;
  decision deferred to post-spec-15.

Both will draft fully once spec 15's research sprint completes.

## Spots that might bite later (worth a deeper look)

These are the specs I'd most want a fresh eye on, in priority order:

### 29 Foliage — biggest single commitment

Full parametric foliage system in v1: trunks + procedural branches +
leaves + variation + wind + LOD across 8 phases. Estimated 25-35
sessions. **This is the largest single Tier 1 system in W5.** If the
scope is wrong, it dominates the W5 build cost.

Worth asking: do we genuinely need full foliage in v1? Or can we ship
trunks-only and live with "v1 trees look weird until Phase 2"? The
phased plan inside spec 29 lays out 8 build phases A-H; we could ship
v1 with just Phases A+B (trunks + procedural branches) and add leaves
+ wind + LOD over time.

Your answer was "full system in v1" — but it was an early answer
before you knew the scope cost. Worth re-examining.

### 30 Atmosphere — Bruneton + volumetric clouds

Both committed for v1. Both real shader work — Bruneton is a known
paper but custom shader port is non-trivial; volumetric clouds are
~2-3 weeks per the WISHLIST estimate. Per pillar 4 (time no
constraint) this is fine, but worth confirming you want both up
front vs ship-clouds-defer-scattering or vice versa.

### 31 Lighting — per-biome lighting + per-biome × per-time color grading

Per-biome color grading is the largest visible-quality lift. Real
LUT authoring work per biome (~1-2 sessions of art-tuning per
biome). For 2 biomes × 3 times-of-day = 6 LUTs. Not breaking, but
real authoring time.

### 19 Kernels — 3 kernels in v1

I committed NoiseStack + Erosion + DemFeature. The DemFeature kernel
is the riskiest — it needs real DEM input handling + feature extraction
code that W4 never built. ~3-5 sessions of kernel work; if v1 ships
without it (NoiseStack + Erosion only), the worlds are still good but
less "grounded in real geology." Re-asking whether DemFeature is v1.

### 35 Water — all 4 phases in v1

You committed full water (lakes + rivers + coasts + underwater).
~10-15 sessions. Same question as foliage: do we need all 4 phases
to call W5 "done," or is lakes+rivers enough for the 2-biome demo
with coasts+underwater as Phase 9.5 work?

### 37 Caves — caves only

Buildings + castles deferred. Schema reserved. The cave system alone
is ~10-15 sessions (SDF authoring + surface-nets meshing + dual-mat
blend at entrance + per-chunk async load). Worth confirming this is
where you want to stop.

### Specs that interact across systems (verify they agree)

These pairs share contracts. Worth checking they're consistent:

- **22 biome catalog + 28 decoration + 29 foliage**: biome catalog
  declares decoration palette ref + foliage species refs. Both
  systems consume the catalog. Should be aligned.
- **27 LOD bake + 28 decoration + 29 foliage + 40 impostors**: all
  consume LOD chains; impostors swap in at distance threshold. The
  LOD-tier numbers must match (decoration's distance bands match
  what LOD bake produces, impostor swap distance is beyond LOD2).
- **38 deformation + 28 decoration + 29 foliage + 33 nav**: deformation
  publishes change broadcast; all of these subscribe + invalidate.
  Should be one event source name, one schema shape.
- **39 persistence + every other spec**: every system's override file
  format follows spec 39's unified shape. Check each system's spec
  uses the same envelope.

## Specs that are mechanical / low-risk

Probably safe to skim or skip on first review:

- 02 contributing lifecycle (spec → plan → build-note pattern; no
  novel decisions)
- 04 godot root allowlist (mechanical preflight)
- 13 quality tiers (W4 carry-over; tier names + schema)
- 26 TRELLIS (W4 carry-over; review-per-subject inheritance)
- 33 nav export (W4 carry-over)
- 34 audio hooks (smallest spec; no audio files ship)
- 41 roads (mechanical A* + override pattern)
- 42 bake recipes (skeleton; deferred)
- 43 plugin packaging (mechanical release process)
- 44 forkability validation (the success-metric test)

## Cross-cutting questions worth your time

1. **Does the v1 scope really finish in a reasonable time?** Per the
   plan, foundations (Phases 0-3) are ~12-20 sessions. Terrain MVP
   (Phase 4) is ~5-10. Ground texture pipeline (Phase 5) ~5-10.
   Second biome (Phase 6) ~3-5. Decoration (Phase 7) ~5-10. Foliage
   (Phase 8) ~25-35. Atmosphere+lighting (Phase 9) ~3-5. Water (Phase
   10) ~10-15 with all phases. Weather (Phase 11) ~3-5. Caves (Phase
   12) ~10-15. Deformation (Phase 13) ~5-8. Persistence (Phase 14)
   ~5-7. Bake recipes (Phase 15) ~3-5. Forkability (Phase 16) ~3-5.
   **Total: ~100-160 sessions.** Consistent with pillar 4 (no time
   constraint) but worth eyes-open acknowledgment.

2. **Are we missing systems that the 2-biome demo will need?** Quick
   mental check: terrain, materials, decoration, foliage, atmosphere,
   lighting, camera, nav, audio hooks, water, weather. Plus
   cross-cutting infra. Plus packaging. That's everything in the
   inventory. Demo should hit it.

3. **What's the wizard game's relationship to W5 during development?**
   The wizard game is a consumer of W5, not part of W5. But forkability
   validation Fork D could be the wizard game. Worth deciding when
   to start wizard-game-side work — probably after Phase 4 (terrain
   MVP renders).

4. **What about non-foliage plants?** Mushrooms, succulents, ferns,
   small flowering plants. They're in the decoration spec (Tier 1)
   not foliage (Tier 1) because they don't have branching topology.
   TRELLIS handles them. Worth confirming that split feels right.

5. **What if renderer research picks something unexpected?** Spec
   15's output could go to nanite-style or hybrid. If it picks
   nanite-style, specs 21 (renderer) + 24 (ground variety) get
   significant rewrites — both are explicitly BLOCKED, so it's
   handled, but the downstream cost is real.

## After review

When you're done:
- Tell me what to fix (push back on specific specs)
- Or say "good, move to Phase 0 repo setup"
- Or say "good, but defer Phase 0 to a fresh session"

Phase 0 (repo setup) is one session: create the `engine/` + `demo/`
+ `pipeline/` tree per spec 01, write top-level README/STATE/ROADMAP,
decide the addon-link mechanism, first commit. Mechanical.

## What's NOT in this review

- Code review (no code exists)
- Implementation plan review (those don't exist yet either — they
  come at Phase 2+ per system)
- Per-system art direction review (per-biome material choices,
  species selection, etc. happen during implementation sprints)
- Spec 15 (renderer research brief) — that's a research SPRINT not a
  decision; reviewed when the sprint output exists
