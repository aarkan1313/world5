# W5 Spec Layer Audit — Findings

> Audit performed by Claude Opus 4.7 on 2026-05-16.
> Read context: `docs/SYSTEM_INVENTORY.md` + all 45 specs under
> `docs/specs/`. Did NOT consult the optional W4.1 retrospective or
> tech-stack audit — assessment is on the W5 spec layer as it stands.

---

## Top-line assessment

The spec layer is **fundamentally sound** in shape: there is a real
lifecycle, real cross-cutting primitives, an explicit pillar tiebreaker,
and a coherent module layout. The author has correctly identified W4.1's
biggest structural mistakes (god-files, missing cross-cutting layers,
doc rot, no formal lifecycle) and structurally pre-empted them. That is
the most-impressive thing here: the *Tier 0* spec set is unusually
disciplined for a clean-slate engine project.

The single **highest-priority concern** is that the per-system frame
budgets do not add up — the additive cost of ambient systems
(atmosphere, clouds, lighting, weather, water, wetness, caves,
decoration LOD pass, wind, color grading) already consumes ~13-14 ms of
the 16.6 ms target budget *before any terrain triangles are rasterized
and before the terrain renderer itself gets a budget*. Either the
budgets are aspirational (in which case the spec layer is lying to
itself) or several of the AAA-target features must be tier-gated more
aggressively than the specs currently commit to.

The second concern is **scope realism**: many systems independently
commit to AAA-target techniques (Bruneton scattering, volumetric
clouds, SDFGI, parametric foliage, virtual texturing as a renderer
candidate, planar reflections opt-in, etc.) for v1. Each individually
is plausible; the aggregate, on no deadline and one builder, is a
multi-year arc that the spec layer does not honestly own.

Would I bet on this engine being delivered? **Yes, partially.** Tier 0
will ship clean. Tier 1's "renderer + terrain backend + materials +
ground variety + texture pipeline + decoration" core will ship,
probably to better quality than W4.1. **Tier 1 foliage and Tier 2 in
full are at high risk of partial delivery** — the foliage estimate
("~25-35 sessions") is the most-optimistic number in the whole spec
set, and the Tier 2 system count (water 4-phase + weather + caves +
deformation + persistence + impostors + roads) is genuinely the work
of a small team, not a single contributor on pillar 4's "no time
constraint." Pillar 4 protects quality, but it does not bend reality
about how long things take.

---

## Critical findings (must address before any code)

### C1. Frame budget arithmetic is unsound

**Severity: critical** (perf pillar at risk from day 1)
**Specs affected: 03, 10, 13, 21, 28, 29, 30, 31, 35, 36, 37, 38, 40, 41**

Adding up the per-spec "Quality bar" frame budgets at the **high** tier:

| System | Budget cited |
|---|---|
| Atmosphere sky shader (spec 30) | ≤ 1.0 ms |
| Atmosphere volumetric clouds (spec 30) | ≤ 2.0 ms |
| Lighting / SDFGI (spec 31) | ≤ 3.0 ms |
| Color grading post (spec 31) | ≤ 0.5 ms |
| Foliage wind shader (spec 29) | ≤ 0.5 ms |
| Water (spec 35) | ≤ 2.0 ms |
| Weather particles (spec 36) | ≤ 1.5 ms |
| Wetness/snow shader (spec 36) | ≤ 0.6 ms |
| Caves (spec 37) | ≤ 1.5 ms |
| Roads runtime (spec 41) | ≤ 0.5 ms |
| Decoration LOD pass (spec 28) | ≤ 1.0 ms |
| Impostors (spec 40) | ≤ 2.0 ms |
| **Subtotal** | **~16.1 ms** |

Frame budget target (spec 03): **16.6 ms** p99 on RTX 3060/4060.

The **terrain renderer itself has no per-frame budget in spec 21** —
its quality bar is "60fps p99" and "≤ 33ms peak", with no numerical
share of the 16.6 ms cited. Foliage geometry rendering (not just wind
shader) likewise has no per-frame number. Decoration rendering
(MultiMesh draw calls, not just LOD pass) is uncounted. The buffer
between the subtotal and target leaves **~0.5 ms for terrain rendering
+ foliage geometry + decoration draw calls + UI overhead**. That is
not feasible.

This is the perf-pillar version of the W4.1 "ClipmapWorld blew geometry
budget" lesson, repeating one layer up. Either:
- the per-system budgets must be re-derived against a shared frame
  budget table (some systems gated to lower tiers, some scope-cut), OR
- the target hardware floor is wrong (3060 cannot deliver this stack
  at 60fps), OR
- the quality bar numbers in individual specs are wishlist values
  and the author knows it — in which case the specs are lying to
  future implementers.

Fix: write a `docs/specs/X_FRAME_BUDGET.md` that owns the per-tier
total budget and assigns named shares to each system. Per-system specs
reference back. No system specs its own perf number in isolation.

### C2. Ground variety status contradicts SYSTEM_INVENTORY

**Severity: critical** (decision authority is unclear; one of the most
load-bearing v1 calls)
**Specs affected: SYSTEM_INVENTORY, 24**

`SYSTEM_INVENTORY.md` (lines 187, 447-451, 484-489) states the
ground-variety architecture decision is **already made**: "ground
variety = siblings + stochastic UV first with compositor as deferred
upgrade." This is repeated as a Tier 4 resolution.

Spec 24 GROUND_VARIETY says: `Status: draft (BLOCKED on
15a_RENDERER_DECISION.md — variety architecture is
renderer-primitive-dependent)`. Its body lists five candidate
architectures with no commitment and a decision tree keyed on the
renderer choice.

These cannot both be true. Either the inventory pre-empted spec 24's
decision (in which case spec 24 should reflect the commitment and stop
being BLOCKED), or spec 24 is right and the inventory's "decided"
status is wrong. The Cyberpunk-style "Option B" (detail texture array)
isn't even mentioned in inventory's Tier 4 resolutions, suggesting
inventory and spec 24 were written at different times by different
mental models.

Pick one. If the decision is genuinely renderer-dependent, the inventory
needs to retract its commitment. If sibling-families + stochastic UV is
genuinely the V1 path regardless of renderer, spec 24 should be
unblocked + drafted to match.

### C3. Renderer research sprint is a single point of failure

**Severity: critical** (cascade risk)
**Specs affected: 15, 21, 24, and transitively the entire Tier 1**

Spec 15 RENDERER_RESEARCH_BRIEF is gating spec 21 TERRAIN_RENDERER and
spec 24 GROUND_VARIETY. Spec 21 in turn is consumed by every visible
scene; spec 24 is "Tier 0 day-1 ambition." The renderer choice
cascades into materials (spec 23 — material array shape may differ
per primitive), into terrain backend (spec 20 — page contract is
shaped around the renderer), into bake recipes (spec 42), into
performance budgets, into impostor swap distances, into nav export
chunk grids.

The spec time-boxes the research sprint at 5 days. **No spec
acknowledges what happens if the sprint slips past 5 days** or if the
prototype fails to hit 60 fps on a 3060. The deliverable check says
"User has reviewed + signed off" — a single human approval gate on the
biggest architectural decision in the whole project, with no fallback
plan.

Additionally, **the decision doc (`15a_RENDERER_DECISION.md`) does not
yet exist**. The cascade is fully unresolved.

Fix: spec 15 should explicitly enumerate fallback paths if (a) the
sprint can't conclude in 5 days, (b) no prototype hits the perf gate,
(c) the chosen primitive's Godot 4.5 support is more partial than
expected. Default-to-clipmap (the known-working W4.1 primitive) is the
honest fallback; the spec should commit to it as the "if all else
fails" answer.

### C4. Kernel cross-impl parity bar references backends that no longer exist

**Severity: critical** (specs cite contracts that can't be honored)
**Specs affected: 19, 20**

Spec 19 KERNEL_SYSTEM quality bar: **"Cross-impl parity: Python ↔
GDScript ↔ C# / GPU produce identical outputs."**

Spec 20 TERRAIN_BACKEND: "V1 ships ONE backend: `GpuTerrainBackend`...
**No CPU fallback in v1.**" The "Open questions" block in spec 20
explicitly notes "when there's only one backend (GPU), there's nothing
to test parity AGAINST."

Kernel parity is now Python (offline/pipeline reference) ↔ GPU compute
(runtime). GDScript and C# implementations are no longer in scope. Spec
19 needs to be rewritten to reflect the actual implementation surface,
or these phantom backends will be cited by every plan doc that
references the parity contract.

Also note: spec 19's "Single sample (Python, in-process): < 50µs" is
a hot-path number; if Python is purely for pipeline + parity-reference
use, this perf number is moot. Restate.

### C5. Climate spec'd as flat per-biome, promised as regional gating

**Severity: significant→critical** (the spec layer over-claims what it
will deliver)
**Specs affected: SYSTEM_INVENTORY, 22, 36**

`SYSTEM_INVENTORY.md` Tier 2 weather says: "Climate kernel (regional
gating from elevation + latitude + distance-from-water)."
Tier 4 resolution: "Climate kernel — FOLDED INTO WEATHER (probably).
Folds into the Weather system spec rather than being separate."

Spec 22 BIOME_CATALOG implements climate as a **flat per-biome
dictionary** (`moisture`, `temperature_c`, `wind_exposure` — three
scalars hardcoded per biome). Spec 36 WEATHER reads those scalars and
weighted-averages by biome weight. **Nothing actually computes
"regional gating from elevation + latitude + distance-from-water."**
The result is the promised "alpine has snow, wetland has rain" effect
without the promised "high altitudes are colder than valleys within
the same biome." The mountain top reads the same temperature as the
mountain base because both share the same biome label.

This is fixable (compute climate from terrain features in the same
auto-biome rules path), but until it is, the inventory needs to stop
promising the regional gating.

### C6. GPU/CPU contract spec is referenced but missing

**Severity: critical** (multiple specs defer to a spec that doesn't
exist)
**Specs affected: 07, 20, indirectly all GPU-touching specs**

Spec 7 JOB_SYSTEM's open question on GPU compute integration defers
"to GPU/CPU contract spec." Spec 20 TERRAIN_BACKEND's references
memory entry `w4_gpu_cpu_contract_2026_05_14` but does not promote it
to a spec. The actual rules (Texture2DRD is GPU-only, no
RenderingDevice from WorkerThreadPool, etc.) live only in the W4 memory
entry that the W5 spec layer is supposed to be the source of truth
*replacing*.

This is exactly the W4.1 mistake the spec discipline was supposed to
prevent: a load-bearing contract living outside the spec set. Without
a GPU/CPU contract spec, the next contributor can violate the rules
freely; spec 7's deferred `GpuJob` design has nowhere to live.

Fix: add a Tier 0 spec (call it `08a_GPU_CPU_CONTRACT.md` or insert
in numbering) that codifies the W4 memory entry's rules + the
`GpuJob` design + the GPU-page lifecycle contract.

### C7. Allowlist (spec 04) forbids `decoration_meshes/` + `cave_meshes/` that other specs require

**Severity: critical** (preflight will fail on day 1 of decoration
work)
**Specs affected: 04, 27, 37**

Spec 04 GODOT_ROOT_ALLOWLIST permits inside `engine/`: `scripts/`,
`scenes/`, `shaders/`, `resources/`, `tests/`, `examples/`, `addons/`
— and *only* these.

Spec 27 LOD_BAKE writes to `engine/decoration_meshes/<category>/<name>/`.
Spec 37 CAVES_INTERIORS writes to `engine/cave_meshes/`.

Neither dir is allowed by spec 04. The preflight script will fail the
moment any decoration mesh is synced. Either:
- spec 04 needs to add `decoration_meshes/` and `cave_meshes/` (and
  `foliage_meshes/`?) to the allowlist, OR
- spec 27 + spec 37 need to nest these under `resources/` (e.g.
  `resources/decoration_meshes/`), OR
- another nesting (e.g. `resources/worlds_runtime_assets/`) is added.

This is a 5-minute fix but currently inconsistent. **Decide before
either spec ships code.**

### C8. Decoration override file naming is inconsistent across specs

**Severity: significant→critical** (file-naming ambiguity at the
contract level)
**Specs affected: 14, 22, 28, 39**

The decoration zone/override file is named differently by different
specs:

| Spec | File name |
|---|---|
| 14 WORLD_CONTRACT (line 53) | `decoration_zones.json` |
| 22 BIOME_CATALOG | uses `splat_overrides` for catalog only |
| 28 DECORATION (line 162) | `decoration_zones.json` |
| 39 PERSISTENCE_AND_AUTHOR_OVERRIDES (line 47-48) | `decoration_overrides.json` |

Spec 39 unifies overrides under one envelope shape; spec 28 wrote its
shape independently. Either spec 39 supersedes spec 28's file naming
(and spec 28 needs to be updated), or both files coexist with subtly
different schemas (which is exactly the W4.1 ad-hoc-per-system pattern
spec 39 explicitly says it's fixing).

This will bite at the first integration. Pick one filename and one
schema.

---

## Significant findings (worth addressing)

### S1. Foliage spec is the most-optimistic estimate in the whole project

**Severity: significant**
**Specs affected: 29**

Spec 29 FOLIAGE estimates "Total: ~25-35 sessions" for the full
parametric foliage system shipped across two biomes, including:
- TRELLIS trunk pipeline
- Tileable bark generation (~6-10 species × variants)
- Procedural branch generator (algorithm TBD — L-systems vs recursive
  vs space-colonization)
- Leaf card pipeline + alpha extraction
- Per-instance baked variation (N variants per species)
- Wind shader
- 4-tier LOD chain bake including impostor handoff
- Per-biome rules + runtime placement
- 6-10 species + sibling variants authored

SpeedTree is a 20+ year company devoted to this exact problem. Open-
source equivalents (Arbaro, the Weber-Penn paper implementations) took
years to reach acceptable quality. Even with FLUX + TRELLIS lifting
the leaf/bark/trunk asset work, **building a parametric branch
generator that produces tree-shaped output across 6-10 species in
~5-7 sessions (Phase B) is highly optimistic.** L-systems alone are
graduate-thesis-scale; "good-looking" L-systems with per-species
parameter tuning is much more.

Realistic re-estimate: **60-100 sessions for the full system** to AAA
quality across two biomes. The spec says "Largest single Tier 1 system
in W5 by implementation cost" — agreed; the number is just too small.

This isn't a fail; pillar 4 says no deadline. But future planning
should not budget against the 25-35 number, and downstream specs (40
IMPOSTORS, 41 ROADS' exclusion patterns) should not assume foliage
delivers on this timeline.

### S2. Atmosphere V1 is significantly more ambitious than W4 — but is also a single spec

**Severity: significant**
**Specs affected: 30**

Spec 30 ATMOSPHERE commits v1 to Bruneton-style atmospheric scattering
**and** volumetric clouds **and** time-of-day API **and** 7 profiles
**and** per-quality-tier gating, with an explicit acknowledgment
("v1 atmosphere significantly more ambitious than W4"). Each is real
work:

- **Bruneton sky**: hand-port of a 2008 paper or adapting open-source
  shader, with precomputed scattering tables. ~5-10 sessions of shader
  work + validation.
- **Volumetric clouds**: raymarched 3D Worley + Perlin. ~5-10 sessions
  to tune for quality + perf budget.
- **Time-of-day**: ~2-3 sessions.
- **Profile catalog of 7 (or expand to weather × time-of-day matrix)**:
  ~2-5 sessions.

Spec implies single Phase / single Plan doc. Realistic: this is 2-3
specs' worth of work, probably should be **split into
30_ATMOSPHERE_SKY**, **30b_ATMOSPHERE_CLOUDS**, **30c_TIME_OF_DAY**.
The Bruneton work alone deserves its own plan doc; sliding it into the
generic atmosphere plan will under-budget it.

### S3. Tier 2 system count is genuinely heavy for "no deadline" one-builder cadence

**Severity: significant**
**Specs affected: 35-41**

Tier 2: water (4 phases, all v1), weather, caves, runtime deformation,
persistence/overrides, impostors, roads. Each spec is well-scoped, but
each is also 5-15+ sessions of real work. Cumulative Tier 2: **easily
60-120 sessions** even before integration testing.

Add Tier 0 (~10-15 sessions), Tier 1 core (~50-100 sessions excluding
foliage), Foliage (~60-100 sessions realistic, per S1), Atmosphere
split (~15-25), Renderer + ground variety (~30-50 once primitive is
chosen), Forkability (~3-5)…

**Realistic total: 200-400 sessions to ship v1 as currently spec'd.**
Pillar 4 says no constraint, but at one session/day that's a year+ of
continuous focused work. The spec layer should at least acknowledge
this scale; the "~100-160 sessions" total in the audit prompt is more
optimistic than the spec set's own implied sum.

Recommendation: define what "v1 minimum viable" means — probably a
2-biome demo with terrain + materials + ground variety + decoration
+ minimal atmosphere + minimal water + camera + nav + audio hooks +
forkability. Foliage v1 could be Phase A trunks only (dead trees) +
defer Phases B-H to v0.2+. Tier 2 spec ordering needs ranking; not
everything ships in v1.

### S4. "Schema version: 1" everywhere with no global registry

**Severity: significant**
**Specs affected: many — 14, 17, 22, 28, 29, 34, 35, 36, 37, 38, 39, 40, 41, 42, etc.**

Almost every spec defines its own `schema_version: 1` in JSON
manifests, version-stamps in artifacts, and migrations triggered on
bump. There's no global table of "which schemas exist, what their
current version is, who's allowed to bump them." Result: at v0.3, when
some specs are at schema_version 2 and others at 1, the world contract
preflight has to know each schema's current canonical version, and
contributors have to know which migrations to write.

Spec 17 VERSIONING covers the *engine* version stamps but doesn't
provide a per-spec schema_version registry. Spec 14 WORLD_CONTRACT
validates each schema independently. The integration between
versioning + schemas + content addressing is real but spec'd in
fragments.

Recommendation: add to spec 17 a "schema registry" section listing
every per-spec schema_version (with auto-generated rollup table in
`engine/resources/schemas/_registry.json`).

### S5. Audio tag namespace has no coordination authority

**Severity: significant**
**Specs affected: 22, 34, 36, 37, 38**

Audio tags are emitted from many systems:
- Biome catalog (`ambient/alpine_high_altitude`) — spec 22
- Decoration point sources (`point/waterfall_loop`) — spec 28
- Zone tags (`ambient/eerie_grove`) — spec 28
- Weather (`ambient/rain_*`) — spec 36
- Caves (`ambient/cave_drip`) — spec 37
- Deformation (`oneshot/impact_small`) — spec 38

Spec 34 AUDIO_HOOKS defines the naming convention (`<type>/<descriptor>`)
but doesn't enumerate or own a registry. The contract is "tag is opaque
to W5; consumer maps tag → audio file." If two systems emit the same
tag name with different intents, or the consumer expects a tag that no
system emits, there's no way to discover the mismatch until runtime
audio drops or doubles up.

Recommendation: spec 34 owns the canonical tag registry — every
spec that emits a tag has to add it to a shared schema, and world
contract validates that consumer's audio bank covers all emitted tags.

### S6. Streaming budget for jobs (`active_jobs` key) has no publisher

**Severity: significant**
**Specs affected: 07, 10**

Spec 10 STREAMING_BUDGET lists `streaming_budget_active_jobs` as a
budget key. Spec 7 JOB_SYSTEM exposes `get_running_count()` and
`get_queue_depth()` but doesn't auto-publish to StreamingBudget. The
budget exists; nobody publishes into it.

Spec 10 says "systems that allocate streamable resources MUST publish"
— jobs aren't resources per se, so JobScheduler is in a grey zone.
Decide: either JobScheduler publishes into StreamingBudget on every
non-trivial state change (chosen budget key `active_jobs`), or drop
the budget key.

### S7. `ultra_far` tier inconsistency

**Severity: significant** (low severity, but multiple-spec sloppiness)
**Specs affected: 13, 31, 40**

`SYSTEM_INVENTORY.md` Tier 0 Quality tiers: "`ultra_far` may or may
not exist in W5 (probably retired — was a 5090 experiment)."

Spec 13 QUALITY_TIERS keeps `ultra_far` in the schema with a "may be
renamed to cinematic or screenshot during the renderer sprint" open
question.

Spec 31 LIGHTING_GI explicitly uses `ultra_far` with full recipe
slot (`sdfgi_probe_extended`).

Spec 40 IMPOSTORS gives `ultra_far` a 500m swap distance.

Either `ultra_far` is in (commit, update inventory), or out (delete
from spec 13 + 31 + 40 + others). Open-status is fine for spec 13's
"open questions" but other specs already wrote `ultra_far` references
assuming it survives.

### S8. Foliage / decoration placement seam is unresolved across both specs

**Severity: significant**
**Specs affected: 28, 29**

Spec 28 DECORATION open question: "Foliage MAY use decoration's
placement layer; alternatively foliage runs its own placement. Decide
during foliage spec."

Spec 29 FOLIAGE open question: "foliage…probably runs its OWN placement
using shared spatial index + budget; coordinates with decoration via
vertical layering."

Each spec defers to the other. The seam is real (canopy foliage
overlaps decoration vertical layering; trees and large rocks may
conflict in placement; both consume biome catalog). Without a
committed decision, the Phase B/C/D foliage work will hit the design
question fresh and revisit it.

Recommendation: pick now (foliage runs own placement, coordinates via
spatial index + a shared exclusion-zone signal) and write it in both
specs.

### S9. Detail textures, building blocks, leaf cards — texture pipeline outputs not in spec 25

**Severity: significant**
**Specs affected: 24, 25, 29, 40**

Spec 25 TEXTURE_PIPELINE adds "detail-overlay" output mode in v1 + acks
SAM segmentation deferred. But:
- Spec 29 FOLIAGE Phase C wants alpha-cutout leaf cards via "texture
  pipeline's --subject mode" — *which isn't in spec 25*. Spec 25 open
  questions mention `tx_subject` as a SEPARATE pipeline.
- Spec 40 IMPOSTORS doesn't use the texture pipeline directly (it
  renders LOD0 via Godot headless) but mentions impostors could reuse
  "texture pipeline's alpha cutouts" per SYSTEM_INVENTORY.
- Spec 24 GROUND_VARIETY Options B/C/D have different texture pipeline
  output requirements that aren't reflected back into spec 25 yet.

Spec 25 is currently spec'd against W4.1's outputs; the new W5
consumers (foliage leaves, ground variety building blocks, etc.)
aren't represented. The pipeline + consumer specs drift.

Recommendation: spec 25 explicitly enumerate every output mode the
downstream specs need: tileable PBR, detail overlay, single-subject
alpha-cutout (`tx_subject`), macro albedo. Define what `tx_subject` is
even if it doesn't ship in v1.

### S10. Spec 11 (ChangeBroadcast) synchronous-by-default + deformation removal pattern conflict

**Severity: significant**
**Specs affected: 11, 28, 38**

Spec 11 defaults subscriptions to synchronous dispatch ("publishes
call subscribers synchronously by default. Provide an `subscribe(...,
{"async": true})` mode that defers callback to next frame? Probably
yes for heavy callbacks. Defer until a consumer asks.").

Spec 38 RUNTIME_DEFORMATION has decoration subscribing to
`terrain_deformation`, querying spatial index for affected instances,
and removing them — potentially many instances per crater. If this
happens synchronously, a crater that hits 200 decoration instances
will rebuild the MMI in the publish call. Frame time spike.

Either:
- spec 38 must require async subscription for this use case, OR
- spec 11 must default to async for heavy subscribers, OR
- spec 38 must defer the rebuild via a Job submitted from inside the
  callback.

Currently none of these are specified. The W4.1 "PITFALLS #10 worker
race" lesson directly maps to this: synchronous heavy callbacks during
publish look exactly like that bug class.

### S11. Renderer module decomposition assertion in spec 21 may not survive primitive choice

**Severity: significant**
**Specs affected: 15, 21**

Spec 21 locks in the renderer module decomposition (`renderer/`,
`streaming/`, `material/`, `diagnostics/`, `TerrainWorld.gd` ≤ 500
lines) **before the primitive is chosen** to "avoid 3900-line god
file." Good principle, but: virtual texturing in particular bleeds
the boundary between `renderer/` and `material/` so heavily that the
clean split may not survive. Nanite-style virtualized geometry
likewise doesn't fit the streaming/material/renderer split — the
whole renderer IS a streaming-driven material pipeline.

If virtual texturing wins, the decomposition gets refactored
post-decision. Spec 21 should explicitly say "decomposition is
indicative; primitive choice may force re-shape, but no god-file
under any primitive."

### S12. TRELLIS + ComfyUI GPU mutex isn't a spec contract

**Severity: significant**
**Specs affected: 25, 26**

Per W4 memory entry `trellis_comfy_mutex`: TRELLIS and ComfyUI cannot
share GPU; must kill one before running the other.

Spec 25 TEXTURE_PIPELINE runs FLUX/ComfyUI. Spec 26 TRELLIS_3D_PIPELINE
runs TRELLIS. Both live in `pipeline/`. **No spec mentions the
mutex**, no spec defines the orchestration that prevents running both
simultaneously. A pipeline orchestrator (e.g. overnight queue job
running texture + TRELLIS in same run) will hit this.

Spec 26 open question mentions it briefly ("defer to plan doc"). The
deferral itself is the problem — this is a contract between pipelines
that needs to be a spec, not a plan-doc detail.

### S13. Erosion kernel as v1 deliverable hides DEM dependency

**Severity: significant**
**Specs affected: 19**

Spec 19 KERNEL_SYSTEM ships ErosionKernel in v1 Sprint 2 — hydraulic +
thermal erosion, GPU compute primary path. Erosion is conventionally
**a global multi-pass simulation** (water flows downhill across the
whole world simultaneously). The spec says "Implemented as a wrapper
kernel that takes another kernel's height field and post-processes
it." OK — but post-processing what? Per-page? Per-chunk?

Erosion is intrinsically global; running it per-chunk produces seams
where water "stops" at chunk borders. Either:
- spec 19 must commit to whole-world pre-bake erosion (not a runtime
  per-page operation; consumes spec 17/12 caching), OR
- the spec must define a chunk-edge-feathering / overlap-region
  mechanism so per-page erosion stays seamless.

The current spec doesn't commit. This is the W4.1 fingerprint-band
seam bug class extended to terrain-feature scale.

DemFeatureKernel (also Sprint 3 v1) has its own dependency hole: "DEM
source handling" is in open questions. Shipping a v1 kernel whose
input source is undefined is risky.

### S14. Spec 6 `--fast ≤ 30s` likely unachievable with gut included

**Severity: significant**
**Specs affected: 06**

Spec 6 TEST_INFRASTRUCTURE: "`--fast` runs in ≤ 30s on dev hardware."
Includes pytest (target 287+ tests by maturity) AND gut headless
(45+ tests). Godot 4.5 headless launch overhead alone is ~3-5s; gut
warmup another second; per-test cost adds. Realistic `--fast` time:
60-120s.

This impacts the dev loop: 30s is "I run it constantly"; 90s is "I
batch a few changes then run." If `--fast` slips to 90s+, contributors
will skip it and the value evaporates.

Recommendation: either tier `--fast` further (pytest only, ≤ 15s,
called `--fastest`; pytest + gut ≤ 90s, called `--fast`), or accept
the 60-90s reality and re-tier the pre-commit gate.

### S15. Spec 04 allowlist `examples/` cap is "defer"

**Severity: significant**
**Specs affected: 04**

Spec 04 open question: "Should `examples/` cap example-scene asset
size? Yes; flag any individual `examples/*/` over (say) 100 MB. Defer
specifics."

The W4.1 candidates trap was 9GB of pipeline scratch — that's
exactly what `engine/examples/<system_name>/` becomes if any example
ships a textured TRELLIS subject + LOD chain (~50MB) per system spec.
12 systems × 50MB = 600MB of examples in `engine/` that Godot will
scan on every import.

Recommendation: ship the cap in v1 (probably 20MB per example dir, 100MB
total examples), not defer.

---

## Minor findings / polish

### M1. CHANGELOG.md location vs spec 01 layout

**Specs affected: 01, 43**

Spec 43 PLUGIN_PACKAGING references "top-level `CHANGELOG.md`"; spec
01 MODULE_LAYOUT shows only `README.md` at top level. Add CHANGELOG.md
+ RELEASE_NOTES.md + INSTALL.md + MIGRATION.md to spec 01's tree.

### M2. `engine/scripts/audio/` and `ai/` open questions in spec 01

**Specs affected: 01**

Spec 01 lists `engine/scripts/audio/` and `ai/` as "if scoped" with
the open question deferring. Inventory has decided: audio = IN (hooks
only), ai = OUT. Spec 01 should reflect: `audio/` directory exists,
`ai/` does not.

### M3. Macro albedo "strongly recommended for worlds > 1km" — but most worlds will be

**Specs affected: 23**

Spec 23 MATERIALS_PBR makes macro_albedo "optional, strongly
recommended for worlds > 1km extent." Inventory + demo target is
implied to be much larger than 1km (8km visibility ship distance per
spec 13). Macro_albedo is effectively a requirement for the engine's
target use case — should be required, not "strongly recommended."
World contract should fail on missing macro_albedo if extent > 1km
rather than warn.

### M4. Decoration blob byte size optimization

**Specs affected: 28**

Instance shape: 2-byte mesh_idx + 28-byte quat (7×f32) + 4-byte scale =
34 bytes per instance. Quaternion as 4×f32 is 16 bytes, not 28 —
re-check the f32 count vs the f32x7 in the spec. (Visible math:
"u16 mesh_idx, f32 x, y, z, qx, qy, qz, qw, f32 scale" = 2 + 9×4 = 38.
Spec says 34. Off-by-4 somewhere.)

### M5. Per-tier kernel complexity vs cross-impl parity

**Specs affected: 13, 19**

Spec 19 quality bar requires "Cross-impl parity: max delta < 1e-5 m for
height" — but spec 19 also says "kernels may have per-tier complexity
knobs — e.g. octave count for fBm." If fBm runs 4 octaves at low and
8 at high, the heights ARE different per tier (by design). Parity is
within-tier, not across-tier. Restate the parity bar to be explicit.

### M6. Spec template `Status: draft | reviewed | shipped` — most specs are draft + no transitions visible

**Specs affected: meta**

All 45 specs are `Status: draft`. The lifecycle (spec 02) says specs
move to `reviewed` after user reads + open questions resolved. Right
now there's no per-spec audit of "is this ready to go to reviewed?"
By the time spec 24 unblocks via spec 15, the 45-spec set should also
have been swept for "what's still really open." That sweep should be
its own pass.

### M7. Spec 06 test infra mentions perceptual diff but no library committed

**Specs affected: 06**

Spec 06 mentions perceptual-diff threshold (0.5% per W4) but doesn't
commit to a library. W4 used some method (probably custom). Pick:
`pixelmatch`, `imagehash`, custom — document.

### M8. Spec 30 atmosphere weather schema slots vs spec 36 reading them

**Specs affected: 30, 36**

Spec 30 defines weather schema slots (`wind_direction`, `wind_strength`,
`precipitation_type`, `precipitation_intensity`, `visibility_m`) but
spec 36 WEATHER overrides them with its own profile output (`rain_intensity`,
`snow_intensity`, `wind_strength`, `wind_direction`). The contract
between "atmosphere holds schema" and "weather produces values" needs
explicit field-by-field mapping; otherwise atmosphere consumers
(materials, terrain shader) read uninitialized fields.

### M9. Spec 33 NAV_EXPORT chunk_grid_n hardcoded to 64

**Specs affected: 13, 33**

Spec 33 NAV_EXPORT example shows `chunk_grid_n: 64`. Spec 13 QUALITY_TIERS
has `terrain_grid_n: 256` at high tier. Nav export is at quarter-rate.
Decision needed: does nav match terrain resolution, or is it always
64 regardless of tier? If decoupled, spec it.

### M10. Spec 18 plugin install method C symlink: Windows mklink requires admin

**Specs affected: 18**

Spec 18's setup script does `mklink /D` on Windows for symlinks. mklink
in cmd or PowerShell requires admin OR Developer Mode enabled on
Windows 10/11. Spec doesn't mention this — first Windows fork
contributor will hit it.

### M11. Spec 16 logging policy: who enforces the lint?

**Specs affected: 16**

Spec 16 says direct `print` / `push_warning` / `push_error` calls
outside `Log.gd` fail preflight. No spec calls out which preflight
script runs the lint, or where it lives. Probably belongs in spec 06
verify-default mode; mention it.

### M12. "Decoration revision" stamp in blob header but no system tracks it

**Specs affected: 28**

Decoration blob header includes `decoration_revision`. Where does this
come from? Pipeline version (spec 17)? Generator revision? Per-rule-
file SHA? Not stated; will be ad-hoc.

### M13. Sibling family directory layout inconsistent with spec 25 output

**Specs affected: 24, 25**

Spec 25's `variants/` subdir holds sibling variants. Spec 24's
sibling-families architecture (Option C) would consume them. The
mapping from `variants/v0_albedo.png` → "sibling family member 0 of
slot X for biome Y" isn't formalized. If spec 24 unblocks to Option C,
the relationship needs definition.

### M14. Persistence spec doesn't define save format conflict resolution

**Specs affected: 39**

Spec 39 says consumer save dirs "look like a world bundle." But what
if the world bundle has `decoration_zones.json` and the save dir has
`decoration_overrides.json`? Same conceptual content, different file
names (see C8). Which wins? Layered? Save shadows bundle? Defer
risk.

### M15. Bake recipe runner "Godot launch + world load + scene setup ≤ 5s" is aspirational

**Specs affected: 42**

Spec 42 quality bar: "≤ 5s on dev hardware." Godot 4.5 cold launch +
world load is rarely under 3-5s alone; plus scene setup; plus headless
init. Either generous (the spec really means "this is a soft target")
or wrong. Re-measure on W4.1 carry-over.

### M16. Spec 13 default `cell_size_m: 32.0` for spatial index unmotivated

**Specs affected: 08**

Spec 08 SPATIAL_INDEX defaults `cell_size_m: 32.0`. No justification.
Decoration LOD pass at typical density (~1 instance/m² at high) =
1024 instances/cell, which is large for an O(N) cell scan. Probably
should be smaller (8-16m) for decoration workloads. Tune per consumer.

### M17. No spec for "GPU compute terrain edit overlay" referenced by spec 38

**Specs affected: 20, 38**

Spec 38 RUNTIME_DEFORMATION assumes the terrain backend (spec 20)
"provides a runtime override mechanism: heightmap pages have a
'base + overlay' pattern. Base is the kernel-generated heightmap
(unchanged); overlay is a sparse delta from deformations."

Spec 20 TERRAIN_BACKEND **does not document this overlay layer.**
Reading spec 20, pages are immutable content-addressed artifacts. The
overlay-on-page contract is implied by spec 38 but unspecified in spec
20. This will cause the deformation work to either (a) re-spec the
backend mid-implementation or (b) ship a different architecture than
intended.

### M18. Spec 33 NAV_EXPORT doesn't depend on foliage but should

**Specs affected: 29, 33**

Spec 33's `Depends on: 20_TERRAIN_BACKEND, 22_BIOME_CATALOG, 28_DECORATION`.
Foliage trunks contribute obstruction per spec 33 line 71 ("trunk
obstructions"). Add `29_FOLIAGE` to depends.

### M19. "Quality bar" rarely cites the visual-comparison method

**Specs affected: many**

Multiple specs cite "visual: reads as X" (atmosphere, lighting,
foliage, ground variety, water) with no concrete acceptance procedure.
Pillar 1 (visual quality first) deserves a concrete review protocol.
Spec 06's capture-based renderer tests cover regressions; bar for
"is this BETTER than before" is silent.

### M20. Carry-over from W4.1 — spec coverage assumes things exist that may not

**Specs affected: 19, 23, 25, 26, 27, 28, 30, 31, 33**

Many specs reference "W4.1 carry-over" (NoiseStackKernel, AtmosphereController,
LightingRecipeController, KernelComposer, terrain shader patterns,
LOD bake scripts, nav export, etc.). The W4.1 source tree contains
debt the W5 retrospective acknowledges. **"Carry-over with refactor"
silently means "rewrite that's anchored to W4 code reading."** The
specs underestimate the rewrite cost when treating them as carry-over
rather than spec-from-scratch with W4 as reference. This is the
"refactor later" anti-pattern in spec form.

Recommendation: each "carry-over" claim audited for: (1) is the W4
code actually shippable as-is into the W5 module layout? (2) what's
the actual rewrite delta? Don't budget against "this is already
written" unless it's verifiable.

---

## Things the author got right

These are real highlights, not flattery:

### G1. The Tier 0 spec set is unusually disciplined

Job system, spatial index, async asset streaming, streaming budget,
change broadcast, content addressing, quality tiers, world contract —
each is a real cross-cutting primitive with a real public API, real
quality bar, real consumer list. The fact that the spec layer
prioritized this set on day 1 (rather than rebuilding terrain first
and patching primitives in later) is the single biggest improvement
over W4.1's structural arc. Most engine projects never write Tier 0
specs at all.

### G2. The audit-prompt + this self-audit pattern

The fact that the author wrote an audit prompt, included a "do not
read REVIEW_BRIEF first" gate to prevent anchoring, and explicitly
asked for brutal honesty over comfort — this meta-discipline is rare
and worth preserving. The whole "spec sheets for everything first,
then build in reasonable order" commitment is the W4.1 anti-pattern
explicitly addressed.

### G3. Three-dir module layout (engine/ + demo/ + pipeline/)

Spec 01 MODULE_LAYOUT's split is structurally correct. The "addon-
shaped from commit #1" commitment, the explicit forbidding of pipeline
scratch inside `engine/`, the symlink-or-submodule install methods,
the per-language test layer separation — all of this comes from W4.1
pain and the response is clean.

### G4. The "LLM-drivability as a property of every spec" framing

Folding LLM-drivability into pillar 3 (architecturally correct) rather
than spinning a "productized LLM agent" system is the right call.
Every spec's Discoverability section + the SITEMAP.json + the
machine-readable validators is the right shape. Specs follow this
consistently.

### G5. Pillar 4 ("time-to-ship is not a constraint") as binding

Frequently engine projects say this and don't mean it. Spec 03's
explicit anti-patterns ("Let's ship it and polish later" / "We'll
refactor once it works") are exactly the rationalizations that erode
quality. The author identifying them as anti-patterns is meaningful.

### G6. The renderer research sprint as a gating decision

Spec 15's commitment to "survey + commit before any renderer code is
written" is correct. W4.1's clipmap-by-default-because-familiar is a
real lesson; the research sprint pattern is the response. Even with
my C3 concerns about cascade risk, the sprint itself is the right
shape.

### G7. World contract preflight extending to every system

Spec 14's "each system spec declares its contract requirements; world
contract collects + runs them" pattern is exactly the W4.1 carry-over
that worked. Generalizing it to every system from day 1 (versus W4.1's
incremental growth) is the structural fix.

### G8. Versioning + migration commitment

Spec 17 commits to "every MAJOR or breaking-MINOR ships with a migration
script. No exceptions." This is the discipline that lets consumers
actually pin to a W5 version + upgrade safely. Most game engines don't
have this; W5 doing it from pre-1.0 is a real differentiator.

### G9. Audio-as-hooks rather than audio-as-system

Spec 34's "engine ships ZERO audio assets, exports tag manifest" call
is structurally correct. Smaller surface, more consumer freedom, no
licensing entanglements, no audio-asset bloat. The pattern matches
the "engine is forkable; consumers customize."

### G10. Test-infrastructure recognition of W4.1's GDScript test gap

Spec 06's three-layer split (pytest + gut + capture-based) directly
addresses the W4.1 gap where GDScript runtime bugs were invisible to
the test harness. Adopting gut rather than building a custom framework
is the right call.

---

## What's missing

### MX1. GPU/CPU contract spec (see C6)
Referenced by multiple specs, not yet written.

### MX2. Frame budget spec (see C1)
No spec owns the per-tier total frame budget + per-system allocations.

### MX3. Documentation health beyond line caps
Spec 05 caps line counts but doesn't define "documentation
correctness": no orphan-link check, no spec-references-spec-that-
exists check, no STATE-matches-code check, no missing-discoverability-
section check.

### MX4. Performance-regression spec
Spec 06 covers capture diff; spec 10 covers budget overrun. But
there's no spec for "perf regression over time": catching a change
that shifts atmosphere from 1ms to 2ms over months. W4.1 had this
informally via profiler scenes; W5 should make it a contract.

### MX5. Per-spec capacity registry
How many decoration instances at high tier? How many active jobs?
How many resident pages? Spec 13 has some, spec 10 has budget keys,
but there's no rolled-up "system capacities at each tier" table.

### MX6. Error handling and graceful degradation
Spec 16 LOGGING covers log levels (`ERROR`, `FATAL`). But no spec
covers what *systems* do on error. If atmosphere fails to load
profile, does it fall back? Does the renderer fail-stop? What's the
contract? Pillar 2 perf gate fails when systems do uncoordinated
fallbacks.

### MX7. Profiler / debug overlay spec
Spec 21 mentions `diagnostics/` module; no spec for what diagnostic
overlays exist, how to enable, how they cooperate.

### MX8. Render-thread vs gameplay-thread contracts
Spec 38 RUNTIME_DEFORMATION says "mesh rebuilds via Job system." Spec
07 JOB_SYSTEM's open question parks GPU job integration. There's no
spec that says "this work runs on render thread, this work runs on
gameplay thread, this work runs on Job worker." W4 had this implicitly
(memory entry on `w4_gpu_cpu_contract_2026_05_14`); W5 doesn't elevate
it.

### MX9. Cross-spec dependency cycle check
Decoration depends on Foliage's spatial-index integration; Foliage
depends on Decoration's vertical-layering; Roads depend on Decoration
exclusion; etc. No spec mechanically detects cycles. Probably no real
cycles today, but a `python -m world5.specs.graph` tool that emits
the dependency DAG would catch any future cycle at preflight.

### MX10. Audio tag registry (see S5)
No spec owns the canonical tag list.

### MX11. Asset library curation
W4 has 399 production meshes; W5 says "review per subject." No spec
for the review process, decision template, or rollup tracking. Will
become an ad-hoc process if not specified.

### MX12. Renderer fallback spec (see C3)
What happens if research sprint fails?

### MX13. Per-world cost grid for roads (spec 41) is undefined
Spec 41 references "cost grid derived from terrain"; the actual
grid resolution, storage format, and generator are unspec'd.

### MX14. Decoration-foliage coordination spec
See S8. Could be a tiny dedicated spec (`28a_DECORATION_FOLIAGE_COORDINATION.md`)
that locks the seam.

### MX15. Per-biome content authoring workflow
For each new biome, a contributor needs to: write biome catalog entry,
generate textures, pick decoration palette, configure foliage species,
configure lighting recipe, configure audio tags, etc. No spec covers
the holistic per-biome workflow. Spec 22 covers the catalog but not
the multi-system per-biome work.

---

## What's over-scoped

### O1. Bruneton + volumetric clouds + 7+ profiles in spec 30 v1
See S2. Atmosphere v1 commits to AAA-target work that should be
phased. A v1 atmosphere of Godot's procedural sky + 4 profiles + ACES
tonemap (i.e. ≈ W4) would be honest; Bruneton + volumetric clouds is
spec 30b/30c work.

### O2. Tier 2 entire scope in v1
Water 4-phase, weather, caves, deformation, persistence, impostors,
roads — each is multi-week+ work. Some are dependencies for others
(impostors needed before foliage Phase H; persistence needed before
deformation save). Tier 2 should be explicitly ranked + at least 2 of
the 7 deferred past v1.

### O3. Foliage v1 scope per spec 29
See S1. ~25-35 sessions for full parametric foliage is the spec's own
"largest single Tier 1 system" understatement.

### O4. World contract + content addressing + versioning + plugin
packaging + forkability validation as separate v1 specs
These are 5 separate specs (14, 12, 17, 43, 44) covering related
concerns. Probably could collapse to 2-3 once shipped: "asset
provenance + versioning" + "release + forkability." V1 doesn't need
all 5 — release packaging (43) + forkability (44) can defer to v0.2+.

### O5. SDFGI + planar reflections + volumetric clouds together at high tier
The Godot 4.5 GPU cost of SDFGI alone on a 3060 is already
near-budget. Adding planar reflections (spec 35 — opt-in but still in
catalog) + volumetric clouds (spec 30) + 4-cascade shadows (spec 31)
puts the per-frame GPU work at "demanding game" territory before any
geometry is drawn. Pillar 2 perf check should validate the combined
cost; spec layer hasn't.

### O6. Spec 39 PERSISTENCE includes a "consumer save-state hook"
that engine doesn't actually own
Spec 39's "consumer can plug in" save-state pattern is documented as
a usage pattern but not a spec contract. It's example code in the
spec. Either commit (spec defines the API consumer plugs into +
validation hooks) or drop (it's documentation, not a contract).

### O7. Octahedral impostors, atlas packing, dynamic lighting hints —
all deferred but in spec 40
Spec 40 IMPOSTORS' deferred features (octahedral, atlas, dynamic
lighting) total >50% of the spec text. Maybe trim deferred to bullets,
leaving the v1 commitment cleaner.

---

## Cross-spec inconsistencies

Listed concisely:

1. **C2: GROUND_VARIETY** status contradicts inventory.
2. **C4: KERNEL_SYSTEM** parity references dead backends.
3. **C5: Climate** promised regional, delivered flat.
4. **C7: ALLOWLIST** forbids decoration_meshes/cave_meshes.
5. **C8: decoration_zones.json vs decoration_overrides.json**.
6. **S7: ultra_far tier** undecided across specs 13/31/40.
7. **S9: Texture pipeline** outputs missing for foliage/impostors/variety.
8. **M2: audio/ + ai/ dir status** in spec 01 vs inventory.
9. **M8: weather schema** in spec 30 vs spec 36 fields.
10. **M9: NAV_EXPORT chunk_grid_n** decoupled from terrain_grid_n.
11. **M17: terrain overlay layer** in spec 38 not in spec 20.
12. **M18: NAV_EXPORT depends-on list** missing foliage.

---

## My honest forecast

### Best case
W5 ships v1 in 18-24 months of one-contributor focused effort with
disciplined scope re-baselining at 6-month intervals. Tier 0 (clean,
on time). Tier 1 ships terrain + materials + ground variety +
decoration + texture pipeline + TRELLIS + LOD bake + minimal
atmosphere/lighting. Foliage ships Phase A (trunks only) — "dead
forest" demo. Tier 2 ships impostors + persistence (minimum needed
for Tier 1 to work) + minimal water (lakes only) + camera + nav +
audio hooks. Weather, caves, deformation, roads defer to v0.2+.
Forkability validation passes on 2 of 3 forks (the pipeline-only fork
exposes real gaps; gets fixed in v0.2). Visual quality matches or
exceeds W4.1 by a clear margin.

### Realistic case
~30 months to v1, with the foliage and atmosphere work taking 2-3×
the estimated time. Tier 2 ships water lakes + persistence skeleton +
impostors; weather/caves/deformation/roads slip to v0.2 or v0.3.
Frame budget gets re-tiered downward (the "high tier" of W5 becomes
what was originally "medium"). One of the three forks hits real
breakage and surfaces a Tier 0 contract gap that requires a v0.x
re-spec sprint. The author writes a W5 retrospective at v0.5 that
identifies the spec-vs-implementation gap honestly. The engine is
genuinely good, but its scope is smaller than v1's specs claim.

### Worst case
The renderer research sprint (spec 15) inconclusively picks virtual
texturing without proving Godot 4.5 can ship it at 60fps on a 3060.
Six months into the renderer build, the prototype hits the perf wall;
the team (one person) has to back out to clipmap and rebuild the
material/streaming integration. Foliage work starts before the
branch-generator algorithm is decided; Phase B drags on as the
algorithm choice is litigated. Tier 0 specs hold up; everything above
them slips by a factor of 2-3. Pillar 4 (no deadline) protects against
shipping broken, but the project enters "always six months from v1"
territory. Forkability validation reveals that the engine works only
in its own demo and the install path breaks subtly across consumer
projects. W5 ends up as an internal-use-only engine that doesn't
achieve the forkability success metric, but does achieve W4.1+
quality for the single internal consumer.

### Most likely
Somewhere between realistic and worst. The Tier 0 spec quality buys
real insurance, but the perf + scope realism (C1, S1, S3, O1, O2, O3)
issues will compound. Mitigating those before any code ships is
genuinely the highest-leverage work the author can do now — fix
the audit's critical findings, then build with confidence.

---

## Closing note

Brutal honesty per the prompt: the spec layer is **the best part of
this project's structural arc** and the **specs themselves are not
shipping the engine** — code will. The 45 specs do many things right
that engines normally botch. They also commit to delivery scope that
implementation reality will renegotiate. The author's commitment to
no-deadline + quality-first is the single most-important protection
here; the danger is that quality-first lets each system grow until
it's perfect-in-isolation while the aggregate frame budget falls
apart (C1) and the whole project's "forkable v1" recedes by a year
each year.

The fixes are all knowable now. Address C1-C8 + S1-S3 + S10 before any
code ships. The rest can drift and self-correct.

---

## Comparison with author's self-review

Read `docs/REVIEW_BRIEF.md` after writing the above. Findings below
compare what the author flagged against what I flagged.

### Things author flagged that I also flagged

- **Foliage spec is the biggest commitment / re-examine "full system in
  v1"** — author called this out in REVIEW_BRIEF "Spots that might bite
  later" as the #1 spec to re-eye, with explicit "your answer was 'full
  system in v1' — but it was an early answer before you knew the scope
  cost." I flagged this as **S1** + **O3**, with a much more aggressive
  re-estimate (60-100 sessions vs author's 25-35). Strong agreement on
  the direction, disagreement on the magnitude.

- **Atmosphere Bruneton + volumetric clouds at once is a lot** — author
  flagged ("worth confirming you want both up front vs ship-clouds-
  defer-scattering"). I flagged as **S2** + **O1**, recommending split
  into 30/30b/30c.

- **Water 4-phase in v1** — author asked "do we need all 4 phases, or
  is lakes+rivers enough." I flagged as **O2** Tier 2 over-scope,
  agreeing several Tier 2 systems (water included) should ship partial
  in v1.

- **DemFeature kernel as v1** — author asked "Re-asking whether
  DemFeature is v1." I flagged as **S13** (DEM source handling
  undefined in open questions).

- **Caves only is the right v1 cut** — author confirming buildings
  deferred. I didn't dispute this; agreed with the schema-reserved
  approach.

- **Ground variety BLOCKED on renderer research** — author owns this
  as a known block. I flagged as **C2** that this BLOCK contradicts
  SYSTEM_INVENTORY's "decided" status. Author was aware the spec was
  blocked but didn't notice the inventory had pre-empted the decision
  (or thought the inventory's claim was provisional).

- **Cross-spec contract pairs need verification** — author listed the
  pairs in REVIEW_BRIEF "Specs that interact across systems." I went
  further and found concrete inconsistencies in those pairs (**C8**
  decoration_zones vs decoration_overrides naming, **M8** weather
  schema fields, **M9** nav chunk grid, **M17** terrain overlay
  layer).

- **Total ~100-160 sessions** — author cites this. I think the foliage
  + atmosphere realism issues (S1/S2) push that to **200-400** as the
  honest spec-implied sum. We agree it's "no constraint" but disagree
  on the implied magnitude.

### Things author flagged that I disagree with

- **Spec 33 NAV_EXPORT as "low-risk, mechanical, W4 carry-over"** —
  author lists nav export as "probably safe to skim." I flagged
  **M18** (missing foliage in depends-on list) + **M9** (chunk_grid_n
  vs terrain_grid_n decoupling). Mild but it's not zero-risk
  carry-over.

- **Spec 34 AUDIO_HOOKS as "smallest spec; no audio files ship"** —
  author marks as low-risk skim. I flagged **S5** (no tag registry
  authority; multiple systems emit tags without coordination).
  The spec is small but the cross-system contract isn't.

- **Spec 41 ROADS as "mechanical A* + override pattern"** — author
  marks low-risk. I flagged it as part of Tier 2 over-scope (**O2**),
  with **MX13** (cost grid undefined) + spec 41's open questions
  themselves flag real architectural debt (path-cave interaction,
  path-water bridges, width-along-length variation).

- **Spec 13 QUALITY_TIERS as "W4 carry-over; tier names + schema"** —
  author marks safe. I flagged **S7** (ultra_far inconsistency across
  specs) + **M5** (per-tier kernel complexity vs cross-impl parity
  contradiction). Carry-over of names is safe; the per-tier numbers
  and the integration with specs 19/31/40 has real friction.

- **Spec 30 atmosphere ("I picked scattering to match")** — agent call
  in REVIEW_BRIEF noting "you said clouds; I picked scattering to
  match." This is exactly the "agent's own opinion masquerading as
  user direction" anti-pattern from the audit prompt. Author was
  upfront about it ("If any feel wrong, push back") but the call is
  significantly increasing scope beyond what the user asked for
  (clouds-only would be cheaper). I flagged this as **S2** + **O1**.

### Things I flagged that author didn't

These are the audit's main value-add beyond the author's self-review:

- **C1 Frame budget arithmetic is unsound** — the author has not
  added up per-system frame budgets across specs. This is the
  audit's #1 finding and isn't in the brief at all. The pillar 2
  perf gate is structurally at risk and the spec layer has no
  central budget owner.

- **C4 Kernel cross-impl parity references dead backends** — the
  GDScript and C# parity contract in spec 19 is no longer enforceable
  after spec 20 dropped those backends. Author missed this.

- **C5 Climate spec'd as flat, promised as regional** — inventory
  promises regional-gating climate; spec 22 ships per-biome scalars.
  The implementation will look-and-feel less weather-rich than the
  inventory claims.

- **C6 GPU/CPU contract spec missing** — referenced by specs 7 + 20,
  doesn't exist. Author noted "GPU only in v1" but didn't see that
  spec 7's GpuJob deferral has no home.

- **C7 Allowlist forbids decoration_meshes / cave_meshes** — concrete
  preflight-failure-on-day-one. Author didn't cross-check spec 04
  against spec 27 + spec 37 outputs.

- **C8 decoration_zones.json vs decoration_overrides.json** — concrete
  filename inconsistency across 4 specs. Author's "verify they agree"
  prompt didn't drill into actual file naming.

- **S6 Streaming budget `active_jobs` key has no publisher** — spec
  10 has the budget key but spec 7 doesn't publish. Cross-spec gap.

- **S10 ChangeBroadcast sync + deformation removal** — sync-by-default
  + heavy decoration cleanup = frame hitch. Architectural risk not in
  brief.

- **S11 Renderer module decomposition may not survive primitive
  choice** — the decomposition in spec 21 is locked before the
  decision in spec 15. Author treats decomposition as architecture
  insurance; I think the insurance may not hold under VT or
  nanite-style.

- **S12 TRELLIS + ComfyUI GPU mutex isn't a spec contract** — known
  W4 memory entry, not promoted to a spec. Will bite at the first
  orchestration that tries to run both.

- **S14 `--fast ≤ 30s` likely unachievable** — concrete dev-loop
  tooling estimate. Author's brief assumes the verify spec is correct.

- **M3 Macro albedo "strongly recommended" should be "required"** —
  for any world that hits the 8km visibility distance from spec 13,
  macro albedo isn't optional. Spec 23 + spec 13 contradict implicitly.

- **M4 Decoration blob byte math off-by-4** — sanity-check finding.

- **M10 mklink requires admin on Windows** — concrete contributor
  friction not in brief.

- **MX1-MX15 systemic gaps** — most of these (frame budget spec, GPU/CPU
  contract spec, perf regression spec, audio tag registry, asset
  curation, decoration-foliage coordination, per-biome workflow) are
  meta-level missing specs. Author's brief doesn't enumerate spec gaps
  beyond the explicitly-BLOCKED ones.

- **The "carry-over from W4.1" cost underestimate (M20)** — author's
  brief treats W4 carry-over as low-cost (spec 13, 33, 26, etc.
  marked "safe to skim because carry-over"). Spec 19 says "carry
  over with refactor." "Refactor" in clean-slate context is "rewrite
  with reference." Cost is comparable to spec-from-scratch in many
  cases. Author appears to underestimate this consistently.

### Calibration summary

Author self-awareness is **good on scope per-system** (the foliage
+ atmosphere + water concerns are exactly the systems an outside
review would also flag) and **weak on cross-spec consistency + frame
budget aggregation + meta-spec gaps**. Author noticed many trees;
audit found additional forest issues.

The single biggest gap between author's review and mine is **C1**
(frame budget). Author's "Cross-cutting question 1" asks "Does the v1
scope really finish in a reasonable time?" — but the more important
question is "Does the v1 perf budget actually run at all on the target
hardware?" Pillar 2 will fail before pillar 4 does.
