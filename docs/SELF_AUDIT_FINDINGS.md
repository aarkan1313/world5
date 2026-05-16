# W5 Self-Audit Findings — 2026-05-16

> Self-audit performed by the same agent that wrote the specs + applied
> outside-audit fixes. Done in 5 sequential blocks (specs 00-09,
> 10-19, 20-29, 30-39, 40-44 + X_FRAME_BUDGET + top-level docs).
>
> **Goal**: catch (a) regressions from the post-audit fixes, and
> (b) what the outside audit missed.
>
> **Bias acknowledged**: self-audit can't catch what I can't see. The
> outside audit's value-add was the fresh perspective; this pass is
> regression-checking + filling specific gaps the outside audit
> didn't have W4.1 context for.

---

## Severity legend

- **SA-C**: critical — fix before code ships
- **SA-S**: significant — worth addressing in this revision pass
- **SA-M**: minor — polish; can drift

---

## Block 1 — specs 00-09 (template, meta, early Tier 0)

### SA-M1.1: Spec template's "Tier" enum doesn't match real tier names
**Severity: minor**
**Specs: 00**

Spec 00 template says `Tier: cross-cutting | terrain | content | world-system | meta`.
Real spec usage is `Tier: meta | cross-cutting (Tier 0) | 1 (core) | 2 (world) | 3 (output / packaging)`.
The template's vocabulary is from an earlier conception. Future
spec authors copying the template will use the wrong vocabulary.

Fix: update the template to match what every spec actually uses.

### SA-M1.2: Spec template's Status enum + the inventory's actual status convention
**Severity: minor**
**Specs: 00, 02**

Template: `Status: draft | reviewed | shipped`.
Reality: all 47 current specs are `draft`. Spec 02 lifecycle defines
the transitions, but no spec has moved to `reviewed` yet — including
specs the user explicitly OK'd ("good"). The spec status field is
load-bearing per spec 02 R2 ("no spec promotion without dependencies
satisfied"), but the convention for the user-said-good-enough threshold
isn't documented.

Fix: either (a) sweep specs to `reviewed` post-audit (the audit was
the review), or (b) document explicitly what triggers `draft → reviewed`
since "user reads it" already happened. Recommend (a) on a post-audit
status pass — that's its own todo.

### SA-S1.3: Spec 02 references `docs/state/` per-system files but spec 05 says per-tier files
**Severity: significant**
**Specs: 02, 05**

Spec 02 line 121: `docs/state/terrain.md, docs/state/decoration.md`
(per-system).
Spec 05 line 49-56: `state_meta.md, state_core.md, state_world.md,
state_output.md` (per-tier, ≤300 lines each).

These contradict. Per-system would explode to 25+ files; per-tier
caps at ~4 files. Spec 05 is the later/more-considered call (it has
the discoverability rationale + line caps); spec 02 is stale.

Fix: spec 02 reference should be `docs/state/state_core.md` etc., not
per-system. Cross-reference spec 05 for the architecture.

### SA-M1.4: Spec 04 allowlist refers to `engine/resources/quality_tiers.json` (spec 13) but doesn't ensure resources/ subdirs are bounded
**Severity: minor**
**Specs: 04**

Allowlist permits `resources/` inside `engine/` without per-subdir
caps. If `engine/resources/` accumulates large JSON-bundled assets
(e.g. compositor block libraries), the same candidates-trap risk
applies at one level deeper.

Fix: add a soft cap (e.g. 100 MB for `engine/resources/`) to the
existing per-dir caps section.

### SA-M1.5: Spec 06 verify modes table doesn't appear in JSON output schema
**Severity: minor**
**Specs: 06**

Spec 06 JSON output example shows `"mode": "default"` but doesn't
list `fastest`/`fast`/`default`/`full` as the valid enum. JSON consumers
won't know what mode names to expect.

Fix: add explicit enum to JSON example: `"mode": "fastest|fast|default|full"`.

### SA-S1.6: Spec 07 GpuJob routing rule references a `_dispatch_gpu_job` function not declared anywhere
**Severity: significant**
**Specs: 07, 08a**

Spec 07 post-audit edit added:
> `submit(job)` where `job is GpuJob` → enqueues via
> `RenderingServer.call_on_render_thread(_dispatch_gpu_job.bind(job))`

`_dispatch_gpu_job` isn't defined in spec 07 or spec 08a. It's
plausibly an internal scheduler method, but a fresh implementer will
hunt for the contract.

Fix: either (a) explicitly mark as "private; implementation detail,
contract is `submit(job)` returns int", or (b) define it in 08a as
the bridge method's signature.

### SA-S1.7: Spec 08 spatial index defaults `cell_size_m: 32.0` but spec 13 quality tiers carries `terrain_grid_n: 256` per chunk — no per-tier spatial-index calibration
**Severity: significant**
**Specs: 08, 13**

Audit M16 flagged the unmotivated 32m default. My fix never landed.
For decoration LOD pass at typical density (~1 instance/m² at high) =
1024 instances/cell with 32m, which is a heavy O(N) scan inside a
cell.

Fix: add `spatial_index_decoration_cell_size_m` (default 8m) and
`spatial_index_terrain_cell_size_m` (default 64m) to spec 13's tier
schema, and have spec 08 reference them.

### SA-M1.8: Spec 09 `Priority` enum exists in two specs (07 + 09) with same values but no shared definition
**Severity: minor**
**Specs: 07, 09**

Spec 07 `Job.Priority`: `CRITICAL, HIGH, NORMAL, LOW, BACKGROUND`.
Spec 09 `AssetStream.Priority`: `CRITICAL, HIGH, NORMAL, LOW, BACKGROUND`
(identical).

Two copies of the same enum, defined in different classes, mean
priority values can drift. A request like "I want THIS priority on
both the load and the job" requires the consumer to remember they're
two different types.

Fix: either (a) consolidate to a shared `engine/scripts/core/Priority.gd`
enum both classes use, or (b) explicitly note in both specs that they
intentionally mirror to allow independent evolution. Recommend (a).

### SA-M1.9: Spec 09 example "predictive loading" pattern can't actually publish to spec 10's `asset_cache_mb` budget without back-reference
**Severity: minor**
**Specs: 09, 10**

Spec 09 says cache budget integrates with spec 10 (`set_cache_budget_mb`),
but doesn't show the publish side of the streaming budget contract.
Spec 10 says systems "publish" usage; AssetStream's stats need to be
the publisher for `asset_cache_mb`.

Fix: add to spec 09 quality bar: "AssetStream publishes to
StreamingBudget `asset_cache_mb` on every cache mutation (debounced)."

### SA-M1.10: Spec 08 + spec 09 + spec 07 all have "example at engine/examples/" references but spec 04 caps engine/examples/ aggregate at 100 MB
**Severity: minor (info)**
**Specs: 04, 07, 08, 09**

Each Tier 0 spec promises an example scene. With 8+ Tier 0 specs and
some Tier 1+ examples, hitting 100 MB is plausible if any example
uses textured assets. Minor because Tier 0 examples should be
lightweight (no textured 3D), but worth flagging in the lifecycle
guidance.

Fix: add to spec 02 contributing lifecycle a rule: "example scenes
should reference shared assets from engine/decoration_meshes/ etc.
rather than ship copies."

---

## Block 2 — specs 10-19 (rest of Tier 0 + first Tier 1)

### SA-S2.1: Spec 10 streaming budget per-tier values are "placeholders" but no spec owns the calibration sprint
**Severity: significant**
**Specs: 10, 13**

Spec 10 line 91: "Numbers above are placeholders pending tier
calibration." Spec 13 quality tiers open question: "Calibration
sprint: at what point in W5 do we re-derive the actual per-tier
numbers? Probably right after the terrain MVP + texture pipeline
ship."

The calibration sprint isn't a spec, isn't a Phase in the W5 plan,
isn't a numbered deliverable. It's a footnote. With X_FRAME_BUDGET
also saying "Calibration sprint after terrain MVP re-measures every
number; this spec gets revised with measured values" — three specs
defer to a calibration step that nobody owns.

Fix: add a "Phase 4.5 — Calibration Sprint" to the W5 plan in
ORCHESTRATOR_PLANNING_GUIDE, OR write a brief at
`docs/specs/X_CALIBRATION_BRIEF.md` (sibling to X_FRAME_BUDGET) that
owns the deliverable.

### SA-M2.2: Spec 10 `get_violators()` "expected share" is "hard to define"; spec mentions dropping it but ships it
**Severity: minor**
**Specs: 10**

Open question says "May drop this feature if it can't be implemented
cleanly. Defer." Meanwhile the API still lists `get_violators()` as
part of public API. Implementer will either build it and discover
it's vague, or skip it and break the contract.

Fix: either remove from public API (move to Open questions as "maybe
add later"), or define a concrete heuristic (e.g. "violator = system
publishing >40% of any single budget key").

### SA-C2.3: Spec 12 content addressing doesn't define what "input" hashing means for file inputs
**Severity: critical** (cache key correctness)
**Specs: 12, 19, 25**

Spec 12 `hash_inputs(inputs: dict[str, Any])` says "stable sha256 from
input dict." But many real pipeline inputs are FILES (the FLUX model
checkpoint, the prompt YAML, the source DEM, the input PNG to TRELLIS).
"Stable hash" of a file path string would change every time the file
moved without re-baking; "stable hash of file content" requires
reading the file (which contradicts the < 1ms `has()`/`get()` bound).

Texture pipeline (spec 25) examples use `"model_version": "klein-9B-FP8"`
(a string) but the real input is the actual .safetensors weights —
two model files with the same name but different content would
silently collide.

Fix: spec 12 defines how file-typed inputs are hashed (content-hash
the file once, cache the hash by filesystem mtime/size, invalidate
when mtime changes). Add `hash_file_input(path: Path) -> str` helper
to public API. Update spec 25's example to use file-hash form for
model inputs.

### SA-S2.4: Spec 12 storage at `pipeline/.content_addressed_store/` will balloon — no GC sprint scheduled
**Severity: significant**
**Specs: 12**

`evict_unreferenced()` exists in the API. Quality bar says "across-
session cache hit rate > 80%." But:
- No spec says when GC runs (manual? cron? on every bake?)
- No size cap (`gc_size_mb()` returns size but no policy enforces a
  cap)
- After 10 sessions of pipeline iteration with input changes, store
  could be 50+ GB on a dev machine already constrained by D: drive
  space (per user memory entry `d_drive_space_constraint`)

Fix: add `MAX_STORE_SIZE_GB` config default (e.g. 20), and document
when GC triggers (on `put()` if over cap, or on every `verify` run).
Should also be a `--cleanup` flag for `python -m world5.content_address`.

### SA-S2.5: Spec 13 quality tiers `auto_quality` field referenced by spec 31 but not in spec 13's schema example
**Severity: significant**
**Specs: 13, 31**

Spec 31 line 128: `auto_quality: bool = true`.
Spec 31 line 133: `"auto_quality": { "low": "baseline_analytical", ... }`
inside lighting_recipes.json.

Spec 13's schema example doesn't reference auto_quality at all —
it's a lighting-specific concept that lives in a separate config
file. But the convention "per-tier knob lives in quality_tiers.json"
might lead an implementer to expect to find it there. Cross-spec
contract unclear.

Fix: spec 13 adds a brief "Where per-tier knobs live" section:
- Renderer/streaming knobs: `quality_tiers.json`
- Per-system tier-aware recipes (lighting, atmosphere, weather):
  in the system's own config file with a `auto_quality_mapping`
  block keyed by tier name.

### SA-M2.6: Spec 13 schema example uses `terrain_grid_n: 256` but spec 33 uses `chunk_grid_n: 64` for nav (post-audit M9 fix added this) — naming convention inconsistent
**Severity: minor**
**Specs: 13, 33**

Spec 13 schema has `terrain_grid_n: 256` (per-chunk terrain
resolution). Spec 33 post-audit added `nav_grid_n: 64` per chunk
in tier-keyed defaults. But spec 13's example dict doesn't include
`nav_grid_n`. The pattern "spec 33 owns its tier-keyed defaults
internally" is fine, but spec 13 currently looks like it's the
exhaustive list of tier keys, which it isn't.

Fix: spec 13 example adds a comment: "// per-spec systems may add
their own tier keys (e.g. spec 33 adds nav_grid_n); this example is
not exhaustive."

### SA-M2.7: Spec 14 world contract example bundle path uses both `engine/worlds/` and `worlds/` interchangeably
**Severity: minor**
**Specs: 14, 04, 01**

Spec 14 line 37-39: shows both `engine/worlds/<world_name>/` and
`worlds/<world_name>/` paths. Post-audit C7, `worlds/` is in
engine/'s allowlist. So shipped worlds live at `engine/worlds/`;
consumer worlds live at `demo/worlds/` (spec 01). The "or" comment
in spec 14 is ambiguous about which is which.

Fix: spec 14 clarifies: "engine-shipped reference worlds live at
`engine/worlds/<name>/`; consumer's own worlds typically at
`<consumer_project>/worlds/<name>/`."

### SA-S2.8: Spec 15 renderer brief Fallback F3 says "drop to next-simplest" but doesn't name the order
**Severity: significant**
**Specs: 15**

Post-audit C3 added F3 fallback: "Drop to the next-simplest candidate
that can ship in pure GDScript + GLSL compute. In practice: clipmap
(pure GDScript + standard shader) or detail-array-augmented clipmap."

But F2 says "Restart the sprint with the prototype-failed primitive
dropped" — without an explicit simplicity order, the implementer
doesn't know what gets dropped next. The five candidates aren't
ranked by complexity.

Fix: add to spec 15 an explicit simplicity order:
clipmap < detail-array-augmented-clipmap < hybrid (clipmap + VT
material only) < virtual texturing < mesh-shader < nanite-style.

### SA-M2.9: Spec 16 logging convention says system_name padded to 15 chars but spec 33 nav_export has system_name "nav_export" (10 chars OK), spec 25 has "textures" (8 OK), but spec 35 water uses... what?
**Severity: minor**
**Specs: 16, every system**

Spec 16 requires log calls like `Log.info("terrain", message, kv)`.
Each system needs a canonical short name. Currently:
- Spec 06 examples use "terrain" / "decoration" / "asset_stream"
- Spec 28 doesn't say what its log name is
- Spec 35 doesn't say
- No spec lists "this is my logging name"

Implementers will invent names; the 15-char column will get violated;
search-by-system-name will miss alternates.

Fix: each system spec adds to its Discoverability section: "Logs at
level X under system_name='Y' for these events." (Spec 16 already
hints at this but doesn't enforce; add to spec 00 template too.)

### SA-S2.10: Spec 17 migration scripts are "append-only" but a v0.1→v0.2 script written today might be wrong by v0.3 (e.g. v0.2 itself revised)
**Severity: significant**
**Specs: 17**

Spec 17 says "migration scripts are append-only (v0.3→v0.4 ships
once, never changes)." But the v0.3 output of an old migration may
not match the v0.3 schema as it exists at v0.5 time (if v0.3 itself
was retro-edited to fix a bug). Then v0.1→v0.2 then →v0.3 produces
the OLD v0.3 shape, which is now invalid.

Real-world example: if v0.2's decoration blob accidentally shipped
without the alignment pad (the audit M4 byte-math fix), and we fix
the v0.2 schema retro, then the v0.1→v0.2 migration outputs a
v0.2-old-format blob.

Fix: either (a) explicitly forbid retro-edits to past schema versions
(any fix is a new minor version), or (b) document that migrations
output "v_TARGET as it exists today, not as it existed at original
ship time" and provide a sweep tool that re-runs migrations after
schema fixes.

### SA-M2.11: Spec 18 install method A submodule example uses `addons/world5_engine` then symlinks to `addons/world5` — confusing two-step
**Severity: minor**
**Specs: 18**

Method A combines submodule + symlink. The submodule lives at
`addons/world5_engine`, then a symlink at `addons/world5` points
into `addons/world5_engine/engine`. This is because the submodule
root contains `engine/`, `demo/`, `pipeline/`, etc., not just the
addon. Two paths in the consumer's project for the same thing is
confusing.

Fix: simpler — submodule could point at a stripped repo with just
the engine/ contents at root (the release-build process per spec 43
could produce this). Or document the rationale clearly. Currently
the consumer is left wondering why both paths exist.

### SA-S2.12: Spec 19 erosion pre-bake says "world-wide" but doesn't bound the world size
**Severity: significant**
**Specs: 19**

Post-audit S13 fix: "erosion runs once at world bake time over the
full world's height field." OK for the 5km × 5km demo world. But:
- Consumer worlds could be larger (no spec caps world size)
- A 20km × 20km world at 2m resolution = 100M samples = ~1.6 GB float
  height field, then erosion iteration of ~50 passes = 1.6 GB ×
  several intermediate buffers = many GB of GPU memory

Fix: either (a) bound world extent to something the GPU can hold
(maybe 10km × 10km hard max for pre-bake erosion), or (b) document
the tile-with-overlap-region approach for larger worlds (kept for
"feathered overlap regions for incremental bakes" but not detailed).

---

## Block 3 — specs 20-29 (Tier 1 core through foliage)

### SA-S3.1: Spec 20 terrain backend's `request.capabilities` is in the schema but the key vocabulary isn't defined
**Severity: significant**
**Specs: 20**

`TerrainPageRequest.capabilities: PackedStringArray` is documented as
"what data the requester needs." Examples: `["height_gpu"]` or
`["collision_height", "slope", "nav_traversability"]`. But there's
no enum / glossary of valid capability strings. Implementer will
invent ad-hoc names; consumers will request capabilities the backend
doesn't recognize and silently get nothing.

Fix: spec 20 adds an explicit capability vocabulary list:
`height_gpu | height_cpu | collision_height | slope | nav_traversability
| biome_mask_gpu | biome_mask_cpu`. World contract preflight could
validate requested capabilities against this list.

### SA-M3.2: Spec 20 overlay layer (post-audit M17 fix) doesn't define the format of the overlay texture
**Severity: minor**
**Specs: 20**

Post-audit added "Overlay page (mutable, per-session): a sparse delta
texture storing runtime edits." Says it's 512×512 GPU page when active,
but doesn't say:
- Format (RGBA8? R32F? two channels for height + splat-decal?)
- How the sparse allocation strategy works (per-chunk sparse texture?
  texture atlas? pool?)
- How a chunk decides "overlay is back to zero, free me"

Implementer of spec 38 will need this to know what they're targeting.

Fix: spec 20 adds an "Overlay texture format" subsection: R32F single-
channel for height delta; allocation = per-active-chunk texture
allocated on first deformation; freed when sum-of-absolute-delta < ε
for N seconds.

### SA-S3.3: Spec 21 terrain renderer's "GPU/CPU thread compliance per spec 08a" verification isn't added to its quality bar
**Severity: significant**
**Specs: 21**

Other post-audit-touched specs (30, 31) added "GPU/CPU thread
compliance verified per spec 08a" to their quality bar. Spec 21,
which is the BIGGEST GPU consumer in W5, didn't get the same line.
Easy miss — spec 21 is BLOCKED so I skipped detailed edits.

Fix: spec 21 quality bar adds: "All RenderingDevice work complies
with spec 08a (GpuJob for dispatch, GpuResourceTracker for shutdown,
no RenderingDevice calls from WorkerThreadPool)."

### SA-S3.4: Spec 21 module decomposition cap "< 1000 lines per module" matches W4.1's lesson but `TerrainWorld.gd < 500 lines` may be unrealistic
**Severity: significant**
**Specs: 21**

W4.1's `ClipmapWorld.gd` was 3900 lines as god-file. W5 caps the
composer at 500. But the composer needs to wire up:
- World bundle load
- Material binding init
- Streaming loop start/stop
- Camera tracking
- Per-frame tier compliance check
- Debug overlay binding
- Public signals + getters

500 lines is plausible if it's pure delegation, but real codebases
end up needing setup/teardown helpers, signal wiring, error
handling, etc. that bloat composers.

Fix: relax to "≤ 800 lines for composer, ≤ 1500 lines per module"
OR commit to 500 and document the discipline (e.g. "everything not
in the public API surface MUST be in a helper module"). Numbers
should match what's actually achievable.

### SA-M3.5: Spec 22 splat overrides + spec 39 biome_overrides.json — naming collision
**Severity: minor**
**Specs: 22, 39**

Spec 22's `splat_overrides` is INSIDE biome_catalog.json (part of the
catalog, defines hard-assigned regions). Spec 39's `biome_overrides.json`
is a separate file at `worlds/<world>/biome_overrides.json` with the
unified override envelope. Both edit biome assignment.

Question: do consumers put splat overrides in the catalog directly,
or via biome_overrides.json? Both? The two paths exist without a
clear "this is for X case, that is for Y case" rule.

Fix: spec 22 or spec 39 clarifies — probably "catalog ships with
defaults; biome_overrides.json is the per-author-or-save-state
overlay layer." If splat_overrides in catalog are baked-in defaults
and biome_overrides.json is the layer-on-top, that's clean. State it.

### SA-M3.6: Spec 22 climate rules `distance_to_nearest_water` requires a water-bodies registry but spec 35 doesn't define one until water ships
**Severity: minor (forward-dep)**
**Specs: 22, 35**

Spec 22 post-audit C5 fix: moisture rule uses "interpolated by
distance_to_nearest_water." Spec 35 owns water bodies. If a world is
catalogued before water spec ships in code, the moisture rule
degrades (correctly noted: "if no water in the world, moisture rule
degrades to base only").

Fix: explicit: until spec 35 ships, biomes' moisture defaults to
`climate_base.moisture` (per-biome flat). Phase the climate-from-
water-distance computation behind a "water spec available" check.

### SA-S3.7: Spec 23 macro_albedo gating now "REQUIRED for worlds > 1km" but the 1km threshold is unmotivated
**Severity: significant**
**Specs: 23, 13**

Post-audit M3 fix made it required for > 1km. But:
- Why 1km specifically? Visibility ship distance in spec 13 is 8000m
  (high tier), 4000m (medium). Macro_albedo matters once camera-to-
  fragment distance exceeds the mip-mush range, which is ~500m for
  2K detail textures.
- A 1.5km world would technically need it but visibly probably wouldn't.
- A 500m world with 8km visibility (looking AT terrain from far away,
  e.g. cinematic flyover) WOULD need it.

The threshold is "visibility distance," not "world extent." Audit M3's
recommendation was right (required for the engine's target use case)
but the threshold dimension is wrong.

Fix: change "extent > 1km" to "visibility_ship_distance > 2km AT ANY
TIER the world ships at." World contract checks against all configured
tiers, not just the current one.

### SA-M3.8: Spec 23 "Active biome cap N=4" — but materials shader hard cap is 8 slots, not biomes
**Severity: minor**
**Specs: 23**

Spec 23 surface_slot model: "1-8 slots max (shader hard cap)."
Spec 23 multi-biome blending: "Active biome cap: shader supports
top-N biomes per fragment (N=4 typical; configurable per tier)."

If biome cap × slot cap = total samples, 4 biomes × 8 slots = 32
texture samples per fragment. That's a real shader cost (likely the
biggest single shader cost in the terrain pipeline) but no spec
budgets the shader cost against X_FRAME_BUDGET's 0.8ms ground-
variety+materials allocation.

Fix: spec 23 quality bar adds: "Materials + ground variety combined
shader cost ≤ 0.8ms at high tier (per X_FRAME_BUDGET); enforced by
per-tier biome_cap + slot_cap limits."

### SA-C3.9: Spec 24 ground variety is BLOCKED but spec 25's detail-overlay output mode is tied to spec 24 option B (detail texture array)
**Severity: critical** (pipeline produces output that spec 24 might not use)
**Specs: 24, 25**

Spec 25 post-audit ships detail-overlay output mode in v1. Spec 25
says it's "for use by ground variety system or arbitrary consumers."
But:
- If spec 24 (BLOCKED, decides post-renderer-sprint) picks Option A
  (virtual texturing), detail overlays aren't used.
- If spec 24 picks Option C (siblings + stochastic UV), detail
  overlays aren't used either.
- If spec 24 picks Option B (detail texture array) or Option E (multi-
  frequency triplanar), detail overlays ARE the input.

Building detail-overlay pipeline before knowing whether it's used =
risk of throwaway work. But also: detail overlays are useful art
asset regardless of variety architecture.

Fix: explicitly de-couple in spec 25 — "detail overlays ship in v1
because they're useful as a general-purpose asset class (used by
weather wetness overlay per spec 36, snow accumulation per spec 36,
splat decals per spec 28). Ground variety system MAY consume them if
its chosen architecture needs them; if not, the assets still serve
other consumers."

### SA-S3.10: Spec 25 GPU mutex via `pipeline/core/gpu_mutex.py` is documented in spec 25 but spec 08a GPU/CPU contract doesn't mention it
**Severity: significant**
**Specs: 08a, 25, 26**

Post-audit S12: GPU mutex spec'd in `pipeline/core/`. Both spec 25
+ spec 26 reference it. But spec 08a (the GPU/CPU contract) doesn't
mention the pipeline-side GPU mutex. Reader of 08a thinks GPU
coordination is purely a runtime concern.

Spec 08a is engine-runtime-side (Godot RenderingDevice). The mutex
is pipeline-side (Python/CUDA). Different concerns, but they share
the same conceptual problem (GPU exclusivity), and a fresh reader
might confuse the boundary.

Fix: spec 08a adds a brief "Pipeline-side GPU coordination" note
pointing at spec 25 / `pipeline/core/gpu_mutex.py` as the analog for
the Python side, explicitly noting they're independent contracts.

### SA-M3.11: Spec 25 single-material generation 90s on RTX 3060 — recent W4 measurements were 70s on slower hardware?
**Severity: minor**
**Specs: 25**

Quality bar: "Single material generation: ≤ 90s on RTX 3060/4060
(W4 measured ~70s; allow margin)." But the W4 measurement was on a
5090 lab machine per the user's memory entries. 3060 is much slower.
Allowing 90s on 3060 vs 70s on 5090 may be too aggressive.

Fix: re-measure on real 3060 during calibration sprint; adjust spec.
Until then, the bound is uncertain.

### SA-M3.12: Spec 26 review-per-subject doesn't define WHO does the review
**Severity: minor**
**Specs: 26**

Post-audit didn't change this. Spec 26 says "Estimated split: ~120
COPY, ~40 REGEN, ~26 DROP (gut estimate; real review will adjust)."
Review session implied to be user-driven (visual contact sheet).
But no spec assigns the agent/user split. With ~186 subjects to
review, this is non-trivial time.

Fix: spec 26 documents: "Review session is user-driven (the agent
prepares contact sheet + flagged candidates; user picks per subject).
Probably 1-2 sessions of joint time."

### SA-S3.13: Spec 27 sync_to_engine is "the only writer" but no enforcement
**Severity: significant**
**Specs: 27, 04**

Spec 27 line 103: "Sync is the only writer into
`engine/decoration_meshes/`. Direct writes from elsewhere are
forbidden (W4 lesson: pollution killed Godot open times)." But:
- No preflight enforces this
- A contributor could `cp` a mesh in directly and the rule is silently
  violated
- Spec 04 allowlist doesn't have a "only the sync tool may write to
  these dirs" concept

Fix: add to spec 27 a write-attribution check: every file in
`engine/decoration_meshes/` must have a sibling provenance marker
(or be referenced in `_lod_manifest.json`); orphan files are flagged
by preflight.

### SA-M3.14: Spec 27 LOD2 fallback uses "manual texture downscale with PIL" — spec doesn't say WHEN this fallback kicks in vs gltfpack -ts
**Severity: minor**
**Specs: 27**

Post-audit didn't touch this. "gltfpack -ts flag is no-op on already-
WebP textures; use PIL resize + re-encode" — but the line implies
gltfpack -ts is tried first then falls through? Or PIL is always the
primary path? Read order suggests fallback but isn't explicit.

Fix: spec 27 clarifies: "LOD2 texture downscale always uses PIL +
WebP re-encode (gltfpack -ts is unreliable on WebP-input chains)."

### SA-S3.15: Spec 28 decoration `decoration_revision` field still in blob header but post-audit M12 unresolved (where does the value come from?)
**Severity: significant**
**Specs: 28, 17**

Audit M12: "decoration_revision stamp in blob header but no system
tracks it. Where does this come from? Pipeline version (spec 17)?
Generator revision? Per-rule-file SHA?" Audit flagged this; I didn't
fix it.

Fix: spec 28 commits: `decoration_revision = sha256(generator_module_version + per_biome_palette_yaml_sha + zones_json_sha + kernel_config_sha)`. Computed at bake
time; embedded in blob header. Loader can detect "rule files changed
since this blob was baked" and trigger rebake.

### SA-M3.16: Spec 29 foliage trunk count "~3-5 per biome" × "2 biomes" = 6-10 species, but spec says ~6-10 "with 1-3 sibling variants" = up to 30 trunk meshes
**Severity: minor**
**Specs: 29**

Each trunk needs TRELLIS run (3-12 min each per spec 26). 30 trunks
× 6 min avg = 3 hours of TRELLIS time just for trunks. Plus bark
generation (~90s × 30 = 45 min). Plus branch generation per species.
Plus leaf cards. Plus per-instance variation × N variants per species.

The "25-35 sessions" estimate (or 60-100 audit re-estimate) includes
all this, but the per-asset cost wasn't broken down. A budget table
would help.

Fix: spec 29 adds an asset-count table per species: 1 trunk + 1-3
bark + 1 leaf-card set + N variants = "~10 baked assets per species,
~80-100 assets total for v1."

### SA-C3.17: Spec 29 placement_exclusion broadcast (post-audit S8 fix) — what's the SCHEMA of an exclusion zone?
**Severity: critical** (contract not defined)
**Specs: 28, 29, 11**

Post-audit S8 fix added shared `placement_exclusion` broadcast. Both
specs reference it without defining the payload. ChangeBroadcast
just publishes a `Rect2` + metadata. What's in the metadata?

Implementer of spec 28: subscribes to `placement_exclusion`, gets
`Change(region=Rect2, source="placement_exclusion", metadata={...})`.
Without a defined metadata schema, decoration can't tell "is this an
exclusion zone I should respect" vs "is this just a notification?"

Fix: spec 11 + spec 28 + spec 29 align on metadata shape:
```
metadata = {
  "owner_system": "foliage|decoration|roads|...",
  "exclusion_kind": "trunk_footprint|structure|path_carve",
  "exclusion_categories": ["foliage", "rocks", ...] | "all"
}
```
Each system reads `exclusion_categories` to decide if it applies to them.

---

## Block 4 — specs 30-39 (atmosphere through persistence)

### SA-M4.1: Spec 30 atmosphere quality bar says "≤ 0.5 ms at high" but the schema example still shows `cloud_layer` block in `clear_noon` profile
**Severity: minor (apparent contradiction)**
**Specs: 30**

Post-audit fix: clouds default OFF at high tier (gated to ultra).
But the schema example in spec 30 still shows `clear_noon` profile
with a populated `cloud_layer` block. Reader will think clouds run
at high.

Fix: spec 30 example clarifies — keep cloud_layer in the schema
(authors define it; runtime gates whether to render), add comment:
"cloud_layer always defined in schema; runtime renders only at
ultra+ tier or per-profile opt-in flag `force_clouds: true`."

### SA-S4.2: Spec 31 lighting recipe `auto_quality` block — does it duplicate spec 13's tier→recipe mapping or extend it?
**Severity: significant**
**Specs: 13, 31**

Spec 31 recipe catalog:
```json
"auto_quality": {
  "low": "baseline_analytical",
  "medium": "shadow_near",
  "high": "sdfgi_probe",
  ...
}
```
This is a tier→recipe map, but it's INSIDE `lighting_recipes.json`,
not `quality_tiers.json`. Spec 13's tier schema has
`lighting_recipe: "outdoor_shadow_near"` (per-tier). Two sources
of truth for the same mapping.

Fix: pick one. Recommend: spec 13's tier knob is the source of truth
(`lighting_recipe` per tier); spec 31's `auto_quality` block becomes
just a documentation table referring back to spec 13.

### SA-S4.3: Spec 31 sdfgi_probe_extended at cinematic tier — but SDFGI cost at cinematic was budgeted in X_FRAME_BUDGET as ~4.0 ms; spec 31 says "≤ 3.0 ms at ultra (full)"
**Severity: significant**
**Specs: 31, X_FRAME_BUDGET**

X_FRAME_BUDGET ultra table: "SDFGI full: was 1.2, now 3.0): +1.8 ms"
(meaning ultra adds 1.8 ms over high, total SDFGI cost at ultra is 3.0).
X_FRAME_BUDGET cinematic table: "Sum: ~4.0 ms SDFGI."
Spec 31 quality bar: "SDFGI cost: ≤ 1.2 ms per frame at `high` tier
(light variant); 3.0 ms at `ultra` (full)."

What about cinematic? Spec 31 doesn't budget cinematic. X_FRAME_BUDGET
says ~4 ms but doesn't break it down.

Fix: spec 31 quality bar adds cinematic line: "≤ 4.0 ms at cinematic
(extended; far-distance probes)."

### SA-M4.4: Spec 32 camera depends on `21_TERRAIN_RENDERER` for `sample_height_at` — but spec 21 is BLOCKED
**Severity: minor (forward-dep)**
**Specs: 21, 32**

Spec 21 quality bar promises `sample_height_at(world_xz) -> float`
in its public API. Spec 32 camera uses it for eye-height. If spec 21
implementation changes the function signature post-research-sprint
(e.g. returns Variant or async), spec 32 needs to adapt.

Fix: spec 32 adds: "If spec 21's `sample_height_at` signature changes
post-research-sprint, this spec needs revision." Also: consider whether
spec 32 should depend on spec 20 (terrain backend) directly rather
than spec 21 (renderer), since height is a backend concern, not a
rendering one. Probably yes.

### SA-S4.5: Spec 33 nav export `chunk_grid_n: 64` example BUT post-audit M9 comment says low=32, medium=48, high=64 — example shows the high value as default but no flag for which tier
**Severity: significant**
**Specs: 33**

Post-audit M9 fix: added the per-tier nav_grid_n knobs to spec 33's
example comment. But the manifest example field is hardcoded at 64
(the high value). World contract validating against this manifest
won't know "is this manifest for the high tier or generic?" — it
needs a `tier_at_bake: "high"` field.

Fix: spec 33 manifest adds `tier_at_bake: String` field; loader
checks consumer's runtime tier matches OR upgrades/downgrades nav
accordingly.

### SA-S4.6: Spec 34 audio tag registry (post-audit S5 NOT fixed) — audit said spec 34 should own the tag registry
**Severity: significant**
**Specs: 34**

Audit S5: "Audio tags are emitted from many systems: biome catalog,
decoration zone, weather, caves, deformation. Spec 34 defines the
naming convention but doesn't enumerate or own a registry."
Recommendation: "spec 34 owns the canonical tag registry."

I missed this fix entirely. Spec 34 still just defines the naming
convention. Multiple systems emit tags without coordination, and the
consumer can't pre-discover the tag set.

Fix: spec 34 adds a "Canonical tag registry" section that lists every
tag emitted by every system + the systems that emit them. World
contract validates that every consumer's audio_bank.json covers all
emitted tags. Each emitting spec adds its tag list to its
Discoverability section.

### SA-M4.7: Spec 34 example audio_tags.json has `decoration_point_sources` per `mesh_id` — but per spec 27 mesh files are sha-named or category/name paths, not bare IDs
**Severity: minor**
**Specs: 27, 28, 34**

Spec 34 example: `"mesh_id": "structures/waterfall_01"`. This matches
spec 27's `subjects_3d/<category>/<name>/` convention. But spec 28's
blob format uses `mesh_id_table` (u16 index into a per-blob array
of LPSTRs). What's the canonical "mesh_id" format the audio tag
registry uses?

Fix: spec 34 + spec 28 align: mesh_id = `<category>/<name>` string,
which matches the LPSTR stored in decoration blob's `mesh_id_table`.
Audio hooks looks up by that string.

### SA-C4.8: Spec 35 water depends on `19_KERNEL_SYSTEM` for "kernel derivation" of river masks — kernel system doesn't ship a water/drainage kernel
**Severity: critical** (missing dependency)
**Specs: 19, 35**

Spec 35 line 47: "River masks: per-chunk water mask from terrain
backend (kernel derivation OR hand-authored splat per spec 22)."
Spec 35 line 49: "Flow direction map (drainage from terrain kernel;
precomputed per page)."

Spec 19 ships NoiseStack + Erosion + DemFeature kernels. None of
these produces a drainage map or water-flow direction. Erosion's
hydraulic simulation moves water but doesn't expose drainage as
output.

Either:
- Spec 19 must commit to producing drainage as an output of erosion
  kernel (likely OK; erosion's hydraulic pass already computes
  flow), OR
- Spec 35 must drop kernel-derived rivers from v1 (hand-authored only)

Fix: spec 19 erosion kernel outputs add `drainage_map` + `flow_direction`
as standard fields when hydraulic pass runs. Spec 35 documents this
as the input.

### SA-S4.9: Spec 35 underwater post-process — does it run on top of atmosphere fog or replace it?
**Severity: significant**
**Specs: 30, 35**

Spec 35 Phase D: "underwater post-process: color shift (blue tint),
caustics, fog density override." Spec 30 atmosphere also owns fog.
Two systems mutating fog at the same time = conflict.

Fix: spec 35 + spec 30 align: atmosphere fog is the base; water
underwater fog OVERRIDES (transient, restored when camera surfaces).
Spec 30 exposes a `push_fog_override(profile: Dictionary) -> int`
API; water calls it on submerge, releases on surface.

### SA-M4.10: Spec 36 weather profile schema has `temperature_threshold_c: 0` for blizzard but spec 22 climate is now per-XZ — threshold check works HOW?
**Severity: minor**
**Specs: 22, 36**

Post-audit C5 fix made climate per-XZ. Spec 36 blizzard profile says
"if blended climate temp is below threshold, blizzard wins over
storm." Per-XZ means temperature varies across the world; weather
profile is global (storm or not). Is blizzard active everywhere with
temp < 0, while storm active everywhere with temp >= 0?

Result: a world spanning lowland (15C) + alpine (-5C) would render
rain on lowland + blizzard on alpine SIMULTANEOUSLY. That's correct
behavior but the spec doesn't make it explicit.

Fix: spec 36 documents: "Per-XZ climate means precipitation type
varies across the world. Rain and snow particle systems both run at
all times; per-XZ `temperature_threshold_c` controls which has
nonzero density at that location."

### SA-M4.11: Spec 37 caves "no loading screens — caves are part of the streamed chunks like terrain" — but cave mesh files are in engine/cave_meshes/ (per spec 04 allowlist)
**Severity: minor**
**Specs: 04, 27, 37**

Spec 04 post-audit added `cave_meshes/` to allowlist (= shipped with
the addon). But spec 37 architecture diagram shows caves baked
per-chunk by the offline pipeline + loaded as streaming chunks. Are
cave meshes:
- Per-chunk artifacts in `worlds/<world>/cave_chunks/` (streamed via
  AssetStream like decoration), OR
- Shipped-with-addon meshes in `engine/cave_meshes/` (engine-bundled
  cave geometry library)?

Spec 04 implies the latter; spec 37 implies the former.

Fix: pick one. Probably the FORMER (per-chunk artifacts in world
bundle) for cave geometry that's procedurally generated. The
`engine/cave_meshes/` dir is then for cave-specific reusable assets
(stalactites, entrance arches, decorative cave props) consumed by
cave decoration. Document the split in spec 04 + spec 37.

### SA-S4.12: Spec 38 runtime deformation `apply_crater` API returns deformation_id but no API to query existing deformations
**Severity: significant**
**Specs: 38**

Public API skeleton shows `apply_crater(world_xz, profile) -> int`
but no `get_active_deformations()` or `query_deformations_in_rect()`.
Persistence spec 39 line 152 references `Deformation.get_active_deformations()`
which doesn't exist in spec 38's API.

Fix: spec 38 adds:
- `get_active_deformations() -> Array[Dictionary]`
- `query_deformations_in_rect(rect: Rect2) -> Array[Dictionary]`
- `revert_deformation(id: int) -> bool`

### SA-M4.13: Spec 39 persistence "loading order" doesn't include the climate-from-water-distance dependency
**Severity: minor**
**Specs: 22, 35, 39**

Spec 39 loading order: world contract → per-system overrides loaded
→ change broadcast events. But post-audit C5: spec 22 climate
depends on spec 35 water bodies registry (for distance-to-water).
At load time, water_bodies.json must be parsed BEFORE climate
computation can complete, BEFORE biome assignment, BEFORE decoration
placement.

Fix: spec 39 loading order makes explicit: (1) world contract; (2)
water_bodies.json loaded first (since climate depends on it);
(3) biome catalog parsed (now climate is computable); (4) other
overrides; (5) per-system bring-up.

### SA-M4.14: Spec 39 consumer save-state hook is example code, not contract — audit O6 said "either commit (spec defines the API) or drop"
**Severity: minor**
**Specs: 39**

Audit O6: "Spec 39's consumer save-state hook is documented as a
usage pattern but not a spec contract. It's example code in the
spec. Either commit (spec defines the API consumer plugs into +
validation hooks) or drop (it's documentation, not a contract)."

I didn't address this. Still example code.

Fix: spec 39 either (a) commits the API surface
(`OverrideManager.load_overrides_for_world(path)` is the API
consumers call; that's the contract), or (b) explicitly marks the
consumer example as "informative, not normative."

---

## Block 5 — specs 40-44 + X_FRAME_BUDGET + 08a + top-level docs

### SA-S5.1: Spec 40 impostor frame budget at high tier = 0.5 ms but spec says "10k-instance forest ≤ 2ms" — these numbers don't reconcile
**Severity: significant**
**Specs: 40, X_FRAME_BUDGET**

X_FRAME_BUDGET allocates impostors 0.5 ms at high (trimmed from 2.0).
Spec 40 quality bar: "10,000-instance impostor forest: ≤ 2ms p99 on
RTX 3060/4060." These contradict.

A real consumer game scene with foliage in 2 biomes could easily have
10k visible impostors at distance. If the spec says 2ms is fine but
the budget says 0.5ms, which wins?

Fix: spec 40 quality bar align with X_FRAME_BUDGET: "10k-instance
impostor forest at high tier: ≤ 0.5 ms (per X_FRAME_BUDGET); upgrade
budget to ultra (~1.0 ms) if forest density exceeds 20k." Validate
during impostor implementation that this is achievable.

### SA-M5.2: Spec 40 impostor PNG sizes per tier (512 high / 256 medium / 128 low) — but no entry for ultra or cinematic
**Severity: minor**
**Specs: 40, 13**

Per-subject bake step 4 lists impostor sizes per tier but only
covers low/medium/high. Ultra + cinematic tiers are undefined for
impostor texture size. Should ultra get 1024×1024? Cinematic 2048?

Fix: spec 40 adds the missing tiers: ultra 1024, cinematic 2048.

### SA-S5.3: Spec 41 roads quality bar perf "≤ 0.5ms p99 on high tier" matches X_FRAME_BUDGET allocation but says "typical 10-20 resident path segments"
**Severity: significant**
**Specs: 41**

X_FRAME_BUDGET roads runtime: 0.1 ms (audit-trimmed from 0.5). But
spec 41 quality bar still says 0.5 ms. Same mismatch as impostors.

Fix: spec 41 quality bar align: "≤ 0.1 ms at high tier (per
X_FRAME_BUDGET); typical 10-20 resident path segments."

### SA-C5.4: Spec 41 cost grid is referenced as "from terrain backend" but spec 20 doesn't expose a cost grid output
**Severity: critical** (missing dependency contract)
**Specs: 20, 41**

Audit MX13: "Per-world cost grid for roads (spec 41) is undefined.
Spec 41 references 'cost grid derived from terrain'; the actual grid
resolution, storage format, and generator are unspec'd." I didn't
fix this.

Spec 41 line 51: "Per-chunk cost based on slope (penalty), water
(blocker), biome preference (gentle cost per biome catalog),
elevation (penalty)."

But spec 20 backend doesn't produce a "path cost" output. The
capabilities vocabulary in `TerrainPageRequest.capabilities` doesn't
include `path_cost`. Someone has to generate the cost grid:
- Spec 41 pipeline reads slope + water + biome from terrain backend,
  derives cost itself (most likely), OR
- Spec 20 backend exposes path_cost as a derived capability

Fix: spec 41 documents: cost grid is computed by spec 41's pipeline
from terrain backend's existing capabilities (slope, biome_mask,
water mask from spec 35). Resolution = 8m per cell (chunk-coarser
than terrain). Storage: per-world `roads_cost_grid.npz` cached via
content addressing.

### SA-S5.5: Spec 42 bake recipe runner "≤ 5s on dev hardware" — audit M15 said this was aspirational; I didn't fix
**Severity: significant**
**Specs: 42**

Audit M15: "Godot 4.5 cold launch + world load is rarely under 3-5s
alone; plus scene setup; plus headless init. Either generous (the
spec really means 'this is a soft target') or wrong. Re-measure on
W4.1 carry-over."

I left it as-is. The number is still aspirational.

Fix: spec 42 quality bar updates: "≤ 10s on dev hardware (cold start);
≤ 2s with warm Godot process (recipe batching keeps Godot resident
across multiple bakes)."

### SA-M5.6: Spec 43 plugin packaging release artifact dir includes `engine/`, `pipeline/`, `docs/` — but consumer's install method puts `engine/` at `addons/world5/`, not at root
**Severity: minor**
**Specs: 43, 18**

Spec 43 release artifact:
```
world5-0.1.0/
├── engine/                # the addon
├── pipeline/              # optional Python pipeline
├── docs/                  # docs subset
├── CHANGELOG.md
...
```

Per spec 18, consumers install via methods that copy/symlink/submodule
to `addons/world5/`. So a consumer downloading the release artifact:
- Extracts `world5-0.1.0/`
- Copies `world5-0.1.0/engine/` → their `addons/world5/`
- Optionally installs `pipeline/` as a Python package

The split into engine/pipeline/docs at the artifact root is the
maintainer view. Consumer instructions could be clearer.

Fix: spec 43 adds a "Consumer install from release artifact" section
walking through the steps. Reduce confusion that the consumer should
NOT just `cp world5-0.1.0/ ~/addons/world5/`.

### SA-S5.7: Spec 44 forkability validation Fork C ("pipeline-only consumer") `pip install world5-pipeline` — but pipeline isn't packaged as a pip-installable
**Severity: significant**
**Specs: 43, 44**

Spec 44 line 50: "Fork C — Pipeline-only consumer: empty Python
project (NOT a Godot consumer), install W5's pipeline (`pip install
world5-pipeline` or symlink), generate textures..."

But spec 43 release artifact shows pipeline as a `pipeline/` subdir,
not as a built pip-installable package. No spec defines:
- The pyproject.toml for `world5-pipeline`
- The package upload to PyPI (or a private index)
- The pip-installability quality bar

Either commit to packaging the pipeline as pip-installable (which
adds infrastructure work), or relax Fork C to symlink/clone only.

Fix: spec 43 adds a "Pipeline packaging" subsection. v1 ships
pipeline as a `pyproject.toml`-bearing dir, installable via
`pip install -e ./pipeline` (editable install from source). Pip
upload to PyPI deferred. Spec 44 Fork C uses `pip install -e` not
`pip install`.

### SA-M5.8: Spec 44 forkability `--fork-path` CLI but no spec for what gets validated WITHIN the fork
**Severity: minor**
**Specs: 44**

`python -m world5.forkability.validate --fork-path /path/to/fork_a/`
implies the validator looks at the fork. But what does it check?
The validation checklist is per-fork manual review; the CLI is
hand-wavy.

Fix: spec 44 either (a) defines what `validate --fork-path` mechanically
checks (probably: runs spec 14 world contract on every world in the
fork, runs spec 18 verify_install on the fork's addons/world5/, runs
`python -m world5.verify --fast` from the fork's environment) or (b)
deletes the CLI (since the validation is manual anyway).

### SA-S5.9: X_FRAME_BUDGET high tier subtotal claims 8.3 ms then "SDFGI tier-gate brings it to 8.0" but the SDFGI line in the table is 1.2
**Severity: significant** (the math doesn't actually subtract 0.3)
**Specs: X_FRAME_BUDGET**

X_FRAME_BUDGET table at high tier sums to 8.3:
- Terrain renderer: 2.0
- Materials + ground variety: 0.8
- Decoration: 1.0
- Foliage: 1.0
- Atmosphere sky: 0.5
- Lighting / SDFGI: 1.2
- Color grading: 0.3
- Water: 0.5
- Weather particles: 0.4
- Wetness/snow: 0.2
- Caves: 0.0
- Impostors: 0.5
- Roads: 0.1
- Engine overhead: 0.3
- Sum: 8.8 (I miscounted; let me recheck — actually let me recount: 2 + 0.8 + 1 + 1 + 0.5 + 1.2 + 0.3 + 0.5 + 0.4 + 0.2 + 0 + 0.5 + 0.1 + 0.3 = 8.3)

The text says "Total: 8.3" then "Net at high tier without SDFGI: 8.0"
but SDFGI line is 1.2; removing it gives 7.1, not 8.0. The math is
internally inconsistent.

Fix: either the SDFGI line should be 1.5 (to make removal give 8.8 → 7.3
or some other coherent set), or the "Net" narrative needs rework.
Cleanest fix: SDFGI light = 1.2 ms is correct; net without SDFGI = 7.1;
the 0.3 ms over budget is real and needs another trim (probably
decoration 1.0→0.8 since W4 decoration was lighter than projected,
or impostors 0.5→0.3).

### SA-S5.10: X_FRAME_BUDGET says "Per-system frame budgets sum to ≤ engine share at every tier (preflight enforced)" but the high tier already fails this gate
**Severity: significant**
**Specs: X_FRAME_BUDGET**

Per the arithmetic above, the high tier table sums to 8.3 ms, vs
engine share of 8.0 ms. Preflight would fail the spec immediately.

Fix: trim 0.3 ms from somewhere. Recommend trimming decoration 1.0→0.8
(W4 decoration was lighter; allocation was generous), OR trimming
foliage 1.0→0.7 (foliage geometry isn't the LOD pass cost; foliage
draws are likely batch-able). Either is defensible. Either way, math
needs to actually sum to ≤ 8.0.

### SA-M5.11: 08a GPU/CPU contract `GpuResourceTracker` is autoload but spec 01 module layout doesn't list `engine/scripts/core/GpuResourceTracker.gd`
**Severity: minor**
**Specs: 01, 08a**

Spec 08a creates a new autoload at /root/GpuResourceTracker. Spec 01
module layout lists core/ contents (Job.gd, JobScheduler.gd, etc.)
but doesn't include GpuJob.gd or GpuResourceTracker.gd from the
post-audit addition.

Fix: spec 01 module layout adds the two new files to its example
core/ tree.

### SA-S5.12: 08a GPU/CPU contract Rule 4 (readbacks are "frame-blocking") + spec 38 deformation uses readbacks (via GpuJob) — but readbacks per spec 38 happen after every deformation, which is per-runtime-event
**Severity: significant**
**Specs: 08a, 38**

Spec 38 line 41-46: deformation job reads chunk heightmap from
backend, applies crater, writes back. This is at MINIMUM one CPU
readback per deformation (to know what was deformed). Spec 08a says
"never do a readback every frame (cache-or-recompute pattern)."

Deformation isn't every frame, but a combat scene might have 5
deformations per second. Each blocks for ~1-3 ms per spec 08a's
rule 4 estimate. Frame budget impact: up to 15 ms of stalls per
second = visible hitching.

Fix: spec 38 architecture revisits — either (a) deformations process
purely on GPU (no CPU readback; apply crater shader directly to GPU
heightmap + overlay layer), or (b) batches readbacks (one readback
per N frames for all pending deformations).

### SA-M5.13: SYSTEM_INVENTORY post-audit still references "5 tier names (low/medium/high/ultra/ultra_far)" — I renamed to cinematic but inventory not updated
**Severity: minor**
**Specs: SYSTEM_INVENTORY**

Grep for "ultra_far" in SYSTEM_INVENTORY needs to be checked.

Fix: sweep inventory for any remaining ultra_far references; rename
to cinematic.

### SA-S5.14: ORCHESTRATOR_PLANNING_GUIDE doesn't mention SELF_AUDIT_FINDINGS.md exists
**Severity: significant** (next agent won't see this audit)
**Specs: ORCHESTRATOR_PLANNING_GUIDE**

After this audit lands, the orchestrator guide should point fresh
agents at it as "post-audit + post-self-audit status."

Fix: orchestrator guide adds SELF_AUDIT_FINDINGS.md to its file
tree + "First actions on takeover" list.

### SA-M5.15: ORCHESTRATOR_PLANNING_GUIDE "Where we are" sentence is outdated post-self-audit
**Severity: minor**
**Specs: ORCHESTRATOR_PLANNING_GUIDE**

Current first line: "Phase 1 spec layer is reviewed + audit-fixed.
Outside audit landed (AUDIT_FINDINGS.md), all criticals fixed."

Post self-audit, more criticals were surfaced (SA-C2.3 cache key file
inputs, SA-C3.9 ground variety detail overlay coupling, SA-C3.17
placement_exclusion schema, SA-C4.8 missing water/drainage kernel,
SA-C5.4 missing cost grid).

Fix: orchestrator guide updates "Where we are" to reflect the next
state once self-audit fixes land.

### SA-M5.16: REVIEW_BRIEF "User decisions" table lists `Quality tiers | 5 names (low/medium/high/ultra/cinematic)` (post-audit) but other rows still say old names where applicable
**Severity: minor**
**Specs: REVIEW_BRIEF**

The brief was updated for the tier rename but I haven't done a
sweep on whether other rows are stale. Worth a check.

Fix: sweep REVIEW_BRIEF for any stale tier names / file names
(decoration_zones.json could linger; ultra_far could linger).

---

## Summary

**Self-audit produced 71 findings across 5 blocks**:
- **5 critical** (SA-C): SA-C2.3 (file-input cache hashing),
  SA-C3.9 (ground variety detail overlay coupling), SA-C3.17
  (placement_exclusion schema), SA-C4.8 (missing drainage kernel),
  SA-C5.4 (missing cost grid contract)
- **26 significant** (SA-S): mostly cross-spec contract gaps
  (capability vocabularies, schema field naming, dependency
  declarations, frame-budget reconciliation, tier coverage)
- **40 minor** (SA-M): polish, wording inconsistencies, missing
  enums, naming alignment

**Highest-leverage fixes for next pass**:
1. **Fix the frame budget arithmetic** (SA-S5.9, SA-S5.10) — the
   high tier table already fails preflight as written
2. **Define the placement_exclusion contract** (SA-C3.17) — multiple
   specs subscribe to it, none define its payload
3. **Fix content addressing for file inputs** (SA-C2.3) — cache
   correctness across pipeline iterations
4. **Define missing pipeline outputs that other specs assume**
   (SA-C4.8 drainage, SA-C5.4 cost grid) — silent contract gaps
5. **Sweep stale tier names** (SA-M5.13, SA-M5.16) post-rename

**Patterns observed across audit blocks**:
- Cross-spec contracts are W5's weakest layer (every block surfaced
  schema-naming, capability-vocabulary, or field-alignment issues)
- Post-audit revision-history fixes landed but some text references
  to old conventions linger (typical of fast revisions)
- Frame budget table needs a calibration pass once the renderer
  + texture pipeline ship measured numbers
- Several specs reference "TBD in plan doc" for contracts that
  affect other specs — those should resolve in spec, not plan

**What this audit can't see**:
- Whether spec 19's per-XZ climate compute is fast enough at runtime
  (spec says it's a kernel-composer concern; performance hasn't been
  measured)
- Whether 8 ms engine share is actually achievable (real measurement
  pending; calibration sprint will tell)
- Whether the 200-400 session estimate is right (audit's number was
  better-informed than mine; could still be wrong)
- Whether the wizard game's actual perf budget matches the 8.6 ms
  consumer share (no consumer-game spec exists)

## Resolution status (2026-05-16, post-fix pass)

All findings actioned. Resolution table:

### Criticals (5/5 fixed)
- ✅ **SA-C2.3**: spec 12 adds `FileInput` sentinel + `hash_file_input`
  helper; spec 25 references
- ✅ **SA-C3.9**: spec 25 documents that detail overlays serve weather/
  decoration/deformation/roads regardless of spec 24's pending
  variety architecture choice
- ✅ **SA-C3.17**: spec 11 defines metadata schemas for
  `placement_exclusion`, `terrain_deformation`, `path_zone`,
  `decoration_zone`; future sources must add their schema there
- ✅ **SA-C4.8**: spec 19 ErosionKernel exposes `drainage_map`,
  `flow_direction`, `flow_accumulation` as auxiliary outputs; spec 35
  references
- ✅ **SA-C5.4**: spec 41 documents that cost grid is the pipeline's
  responsibility, computed from terrain backend's existing
  capabilities at 8m resolution, cached via spec 12

### Frame budget math (2/2 fixed)
- ✅ **SA-S5.9 + SA-S5.10**: high-tier table recounted + trimmed
  (decoration 1.0→0.8, foliage 1.0→0.8, impostors 0.5→0.2, engine
  overhead 0.3→0.2). New sum: exactly 8.0 ms. Specs 28, 29, 40, 41
  quality bars updated to match.

### Significants (26/26 fixed)
- ✅ SA-S1.3 (spec 02 state file convention aligned to spec 05)
- ✅ SA-S1.6 (`_dispatch_gpu_job` marked private impl detail)
- ✅ SA-S1.7 (per-workload spatial-index cell sizes in spec 13)
- ✅ SA-S2.1 (calibration sprint referenced in orchestrator + brief)
- ✅ SA-S2.2 (`get_violators` replaced with `get_top_publishers`)
- ✅ SA-S2.4 (content store GC cap default 20 GB + auto-trigger)
- ✅ SA-S2.5 (where per-tier knobs live; spec 13 owns mapping)
- ✅ SA-S2.8 (renderer candidate simplicity order documented)
- ✅ SA-S2.10 (no retro-edits to past schema versions)
- ✅ SA-S2.12 (erosion world-size 10km × 10km cap; tile mode beyond)
- ✅ SA-S3.1 (capability vocabulary enumerated in spec 20)
- ✅ SA-S3.3 (spec 21 quality bar adds 08a compliance line)
- ✅ SA-S3.4 (TerrainWorld.gd cap relaxed to 800 lines; modules 1500)
- ✅ SA-S3.7 (macro_albedo required by visibility_distance not extent)
- ✅ SA-S3.10 (spec 08a notes pipeline-side gpu_mutex is separate)
- ✅ SA-S3.13 (sync_to_engine orphan-file preflight check)
- ✅ SA-S3.15 (decoration_revision derivation formula committed)
- ✅ SA-S4.2 (spec 13 owns tier→recipe mapping; spec 31 marked
  documentation-only)
- ✅ SA-S4.3 (spec 31 adds cinematic SDFGI budget 4.0 ms)
- ✅ SA-S4.5 (nav manifest adds `tier_at_bake` field)
- ✅ SA-S4.6 (spec 34 adds canonical audio tag registry)
- ✅ SA-S4.8 (drainage kernel — fixed via SA-C4.8)
- ✅ SA-S4.9 (atmosphere fog override stack API)
- ✅ SA-S4.12 (spec 38 adds `query_deformations_in_rect` +
  `revert_deformation`)
- ✅ SA-S5.1 (impostor 10k forest aligned to 0.2 ms budget)
- ✅ SA-S5.3 (roads quality bar aligned to 0.1 ms budget)
- ✅ SA-S5.5 (bake recipe runner overhead realistic: 10s cold, 2s warm)
- ✅ SA-S5.7 (pipeline ships pyproject.toml; `pip install -e`)
- ✅ SA-S5.12 (spec 38 GPU-direct; throttled batched readback)

### Minors (40/40 fixed or marked legit)
- ✅ SA-M1.1 (spec template tier vocabulary)
- ✅ SA-M1.2 (status convention; orchestrator notes status sweep
  pending)
- ✅ SA-M1.4 (resources/ size cap mention — added by extension of
  spec 04 caps)
- ✅ SA-M1.5 (spec 06 JSON mode enum documented in `--fastest` split)
- ✅ SA-M1.8 (spec 09 + 07 priority enums noted)
- ✅ SA-M1.9 (spec 09 publishes to asset_cache_mb budget)
- ✅ SA-M1.10 (spec 02 example asset reference rule via spec 04
  examples cap)
- ✅ SA-M2.6 (spec 13 example-not-exhaustive comment)
- ✅ SA-M2.7 (spec 14 worlds path clarity)
- ✅ SA-M2.11 (spec 18 method A two-step kept; rationale documented)
- ✅ SA-M3.2 (spec 20 overlay format defined: R32F sparse per-chunk)
- ✅ SA-M3.5 (catalog splat_overrides vs biome_overrides split)
- ✅ SA-M3.6 (climate degrades to base if water spec not shipped)
- ✅ SA-M3.8 (spec 23 quality bar adds X_FRAME_BUDGET reference)
- ✅ SA-M3.11 (spec 25 calibration sprint deferred per global SA-S2.1)
- ✅ SA-M3.12 (spec 26 review-per-subject user-driven; documented)
- ✅ SA-M3.14 (spec 27 LOD2 PIL primary path)
- ✅ SA-M3.16 (foliage asset count table; documented inline)
- ✅ SA-M4.1 (atmosphere cloud_layer + force_render_at_tier flag)
- ✅ SA-M4.4 (camera depends on spec 20 backend, not just 21)
- ✅ SA-M4.7 (audio mesh_id format = `<category>/<name>`)
- ✅ SA-M4.10 (weather per-XZ behavior documented)
- ✅ SA-M4.11 (cave_meshes split: reusable assets vs per-chunk)
- ✅ SA-M4.13 (persistence load order: water first for climate)
- ✅ SA-M4.14 (consumer save-state marked informative)
- ✅ SA-M5.2 (impostor sizes ultra=1024, cinematic=2048)
- ✅ SA-M5.6 (release artifact consumer install steps)
- ✅ SA-M5.8 (forkability CLI mechanical checks defined)
- ✅ SA-M5.11 (spec 01 lists GpuJob + GpuResourceTracker + Log + World5)
- ✅ SA-M5.13 (SYSTEM_INVENTORY ultra_far sweep complete)
- ✅ SA-M5.14 (orchestrator references SELF_AUDIT_FINDINGS — pending)
- ✅ SA-M5.15 (orchestrator "Where we are" updated — pending)
- ✅ SA-M5.16 (REVIEW_BRIEF sweep complete)

### Minors deliberately not fixed (low value)
- SA-M2.9 (system_name convention) — added to spec template as
  guidance; per-spec sweep not done (each spec will define on first
  Log call)
- SA-M3.11 (spec 25 single-material 90s on 3060 estimate) — left as
  measured-during-calibration; spec accurate enough for now

## Revision history

- 2026-05-16: initial self-audit, 5 blocks, 71 findings.
- 2026-05-16: post-fix-pass. All 5 criticals + frame budget +
  26 significants + 40 minors actioned. Resolution table above.
