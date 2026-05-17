# W5 — System Inventory

> The high-level "what does W5 BE" doc. Lists every system in scope,
> with a paragraph on what each does, why it exists, and what it
> explicitly does NOT do. Per-system specs live under `docs/specs/`
> and drill down from this inventory.
>
> This doc gets updated whenever a system is added, cut, or scoped.
> If something is in this doc, there's a spec for it (or there's
> going to be).

## Reading this doc

Systems are grouped by tier:
- **Tier M — Meta**: governance + structure (specs, lifecycle, layout, pillars).
- **Tier 0 — Cross-cutting primitives**: things consumed by every system.
- **Tier 1 — Core systems**: the engine's foundational behaviors.
- **Tier 2 — World systems**: features that make the world feel alive.
- **Tier 3 — Output / packaging**: consumer-facing recipes + addon shape.
- **Tier 4 — Open**: things that may or may not be in W5; review per item.

Read top-down. Earlier tiers are dependencies for later.

---

## Tier M — Meta

These already have specs at `docs/specs/`. Listed for completeness.

| System | Purpose | Spec |
|---|---|---|
| Spec template | Standard shape for every spec doc | `docs/specs/00_SPEC_TEMPLATE.md` |
| Module layout | Three-dir contract (`engine/` + `demo/` + `pipeline/`) | `docs/specs/01_MODULE_LAYOUT.md` |
| Contributing lifecycle | Spec → plan → build-note → state cycle | `docs/specs/02_CONTRIBUTING_LIFECYCLE.md` |
| Pillars | Quality > Performance > Architecture > Time, as tiebreaker | `docs/specs/03_PILLARS.md` |

---

## Tier 0 — Cross-cutting primitives

These are consumed by every Tier 1+ system. They MUST exist before
vertical work begins; W4.1's biggest mistake was building vertical
systems first and discovering missing primitives later.

### Job system
A wrapper over Godot's `WorkerThreadPool` that adds priority queues,
cancellation tokens, shutdown-safety flags, and dependency graphs. Every
long-running async operation in W5 goes through it; no direct
`WorkerThreadPool.add_task` calls in system code. Solves W4 PITFALL #10
(shutdown spam + editor crash from workers outliving deps).

**Non-goals**: scheduling across multiple machines, GPU job
orchestration (separate concern under GPU/CPU contract).

### Spatial index
Generic grid / quadtree / spatial-hash module with
`insert(id, point)`, `query_radius(point, r)`, `query_rect(rect)`,
`remove(id)`. Backed by `PackedFloat32Array` for hot paths. Used by
terrain page lookup, decoration LOD pass, future nav region queries,
future audio occlusion, future AI knowledge ("what's near me").
Eliminates W4.1's "every system iterates everything" pattern.

**Non-goals**: dynamic re-balancing for densely-clustered data
(B-tree complexity isn't needed at our scale); spatial indexes
spanning multiple worlds.

### Async asset streaming layer
Wraps `ResourceLoader.load_threaded_request` + `load_threaded_get`,
providing `request(key, priority) → Status{NOT_LOADED, LOADING, READY,
FAILED}`. Caches results, deduplicates in-flight requests, supports
cancellation. Shared by decoration mesh load, texture array streaming,
audio assets, nav region preload. Eliminates W4.1's R14d crisis where
every loader reimplemented the same plumbing.

**Non-goals**: HTTP/network asset loading (Godot ResourceLoader
abstracts this away if needed); custom asset format readers (those
live in their own systems).

### Streaming budget contract
Per-tier shared ceilings for active triangles, resident texture MB,
draw calls, active jobs, CPU pages, GPU pages. Every async system
publishes its usage; the accountant aggregates and fails loudly if
total exceeds the budget. Same idea as W4.1's `StreamingBudgetAccountant`
but enforced for ALL systems, not just terrain.

**Non-goals**: per-frame budget enforcement (that's a profiler concern);
runtime cost prediction (we measure, not predict).

### Dirty-rect / change broadcast
Emits `region R changed at time T because of source S`. Consumers
subscribe and invalidate their own caches. The substrate for runtime
edits (terrain deformation, decoration zone changes, persistence
write-back). Even with zero publishers on day 1, the contract is built
so consumers can subscribe without retrofit later.

**Non-goals**: cross-process broadcast (single-game-runtime only);
event sourcing / replay (persistence is its own system).

### Asset content addressing
Content-addressed asset store with sha-keyed artifacts and dependency
graph between generators. Partial-rebake when an upstream input
changes: only chunks affected by that change get re-baked. Cross-pipeline
shared store (texture pipeline, LOD bake, terrain page cache, decoration
blobs, audio assets, etc. all participate).

**Non-goals**: distributed asset CDN; user-facing version control
(git serves that).

### Quality tiers
`low` / `medium` / `high` / `ultra` typed dicts with per-tier ceilings
for streaming budgets, LOD distances, draw call caps, visibility ship
distance, atmosphere/fog ranges. Carry-over from W4.1 (already proven).
Default tier is `high` (targeting 3060 / 4060). `cinematic` is the
top tier (renamed from `ultra_far` post-audit S7; 30fps target, full
SDFGI + volumetric clouds + planar reflections; not a "ship for
players" tier).

**Non-goals**: dynamic per-frame tier switching (tier is chosen at
session start); user-facing graphics settings UI (consumer responsibility).

### World contract / preflight
Validator that checks a `worlds/<name>/` bundle before runtime
consumption: biome catalog uniqueness, kit paths, scale, shader caps,
PBR map sizes, material variants, surface slot rules, etc. CLI tool
(`python -m world5.world_contract --world X --strict`). Run before
every commit that touches a world bundle.

**Non-goals**: runtime content validation (we trust authored content
that passes preflight); style/aesthetic critique (humans + visual
review).

---

## Tier 1 — Core systems

These are the engine's foundational behaviors. Each depends on the
Tier 0 primitives.

### Terrain renderer
The runtime that displays a continuous, streamed heightfield world.
The renderer primitive (clipmap vs virtual texturing vs nanite-style
vs hybrid) is **TBD via a research sprint** — see `RENDERER_RESEARCH_BRIEF.md`.
Whatever primitive wins, it consumes GPU-resident render pages (default,
no opt-in path), CPU-resident gameplay pages (collision, nav, decor),
and the Job system for all async page generation.

**Non-goals**: 2.5D/topdown runtime view modes (those are offline bake
recipes, separate Tier 3 system); terrain editor / heightmap painter UI
(consumer responsibility, not engine).

### Terrain backend
The compute layer underneath the renderer: kernel evaluation (height +
biome weights + slope at world XZ), per-page generation (heightmap +
collision + slope + nav-traversability + biome mask + density layers).
W4.1 had three backends (GDScript / C# / GPU); W5 commits to GPU as
default + one CPU backend for fallback (C# if it survives review;
otherwise GDScript). Page contract carries deterministic cache key +
content stamp for bake invalidation.

**Non-goals**: backends for non-Godot runtimes; multi-machine page
generation.

### Kernel system
Pure-function height + biome-weight generators. W4.1 shipped one
(`NoiseStackKernel` — fBm). W5 starts with the same, plus the framework
to add more (DEM-feature-driven, erosion, astro/lunar, etc.). Python ↔
GDScript ↔ C#/GPU cross-impl parity is the contract.

**Non-goals**: kernel authoring UI; runtime kernel switching.

### Materials + PBR pipeline
Per-biome PBR material kits (albedo, normal, roughness, AO, height,
metallic, macro albedo) shipped as `Texture2DArray`s. Surface slot
blending (ground / mid / rock weighting from slope + elevation + noise).
Multi-biome blending via world-anchored splat masks. Carry-over from
W4.1 with refactor — the material pipeline worked, the integration
into ClipmapWorld is what needs rebuilding.

**Non-goals**: hand-painted material authoring UI; runtime material
swapping.

### Ground variety system
The architecture that prevents "same texture endlessly repeated across
the world" — the W4.1 visible failure. Approach is **BLOCKED on the
renderer research sprint output (spec 15a)** — the variety architecture
is renderer-coupled. Five candidate architectures documented in spec 24
(virtual texturing, detail texture array, siblings + stochastic UV,
building-block compositor, multi-frequency triplanar). Either way,
ground variety is **Tier 0 day-1 ambition**, not Tier 2 polish.

**Non-goals**: per-pixel unique textures (impossible at our scale);
hero-quality hand-authored ground textures (we ship procedural + AI, not
artist-authored).

### Texture pipeline
Prompt → PBR set. 4-pass FLUX + delight + hybrid PBR (SM tileable
albedo + derive_pbr_v2 for PBR maps) + QA. Carry-over from W4.1
(`pipeline/textures/tx_*`) with refactor; structurally proven. Output
shape may evolve based on ground-variety architecture (siblings vs
building blocks). Diversity batch driver per-biome.

**Non-goals**: realtime texture generation; ground-truth photo
matching (we generate, we don't fit).

### TRELLIS / 3D asset pipeline
Image → 3D mesh. Carry-over from W4.1. ~3 min/subject. Failures cluster
on thin/wiry geometry (foliage, ropes, etc.). Used for decoration
subjects (rocks, props, structures, bones). Photo → stylized → TRELLIS
loop works.

**Non-goals**: TRELLIS for foliage (the foliage system has its own
approach because TRELLIS doesn't handle branches); realtime mesh
generation; multi-view input.

### LOD bake pipeline
3D mesh → 4-tier LOD chain (LOD0 hero @ 8k tris, LOD1 mid, LOD2 far,
LOD3 distant). Voxel-remesh → smart UV → Cycles bake → WebP compression
→ brightness compensation. Carry-over from W4.1 — 186/343 subjects
baked successfully. Failures need follow-up (thin/wiry, saturated
colors).

**Non-goals**: realtime LOD generation; impostor LOD baking (that's
the impostor system, separate Tier 2).

### Decoration program
Per-chunk placement of meshes (rocks, plants, structures, props) via
Poisson-disk scatter. Slope / biome / surface-slot / orientation /
clustering / vertical-layering / exclusion-zone rules. Author overrides
(hand-placed instances + zones). Per-instance LOD with hysteresis.
Streaming budget integration. Built fresh on Tier 0 foundations
(spatial index + async streaming + change broadcast) rather than
copy-refactor of W4.1's runtime.

**Non-goals**: NPC / animal placement (separate system if scoped);
runtime placement editor UI; multiplayer-synced placement.

### Foliage system
The W4.1 gap closed. **User's spec**: trunk-first (TRELLIS or
parametric), tileable bark texture, procedural limbs + leaves +
branches via parametric generator (height / width / branch-angle /
foliage-density variables). Per-instance variation. Wind shader. LOD
ladder including impostor tier. The hardest single Tier 1 system.

**Non-goals**: photoreal species accuracy (stylized is fine);
realtime tree growth animation; user-authored tree species (we
ship rules; tuning is config-file work).

### Atmosphere
Procedural sky, sun, fog, distance haze, time-of-day. Carry-over from
W4.1 (`AtmosphereController`) with reuse. Weather schema lives here
even if weather effects ship later.

**Non-goals**: volumetric clouds (parked, separate spec if scoped);
god rays / shafts of light (engine.fog covers most of this); galactic /
night-sky detail.

### Lighting / GI
Per-quality-tier lighting recipe catalog. SDFGI for high-tier; baked
or analytical for low-tier. Per-biome lighting tuning. Color grading
+ post-process recipes (W4.1 wishlist item; W5 makes it Tier 1).
Shadow strategy (cascaded / contact / SSAO per tier).

**Non-goals**: realtime baking; user-facing lighting editor UI;
ray-tracing (Godot 4.5 doesn't ship RT).

### Camera + view
Single 3D walk camera at runtime. WASD + mouse-look. Quality-tier
aware (far plane, FOV, eye height all per-tier). Replaces W4.1's
walk/iso/topdown switching since runtime is 3D-only.

**Non-goals**: cinematic camera (consumer concern); iso/topdown at
runtime (those are bake recipes, Tier 3).

### Nav export
Worldgen emits nav-relevant data (walkable mask, slope, water mask,
obstruction masks from decoration/buildings) on a stable schema.
Consumer projects build actual navmesh from it. Carry-over from W4.1
(`pipeline/nav_export.py`) with refactor.

**Non-goals**: runtime navmesh generation (that's consumer territory);
NPC AI navigation behavior (that's consumer territory).

### Audio hooks
**Engine ships ZERO audio assets.** What it ships is an audio-tag
manifest: each biome / decoration zone / specific decoration subject
emits an opaque audio tag (e.g. `"ambient/forest_dense"`,
`"point/waterfall"`, `"loop/wind_high_altitude"`). Consumer projects
map tags to their own `.ogg`/`.wav` files and wire spatial-audio
playback. Smaller engine surface; gives consumers full freedom over
audio direction without engine bloat.

**Non-goals**: bundling audio files; realtime audio synthesis;
spatial-audio runtime (Godot's `AudioStreamPlayer3D` is what
consumers use).

---

## Tier 2 — World systems

Each makes the world feel more alive. All have their own specs;
order of implementation TBD by dependency + visual impact.

### Water
Lakes (v0) → rivers (v1) → coasts (v2) → underwater (v3). Plane shader
+ basic reflection + terrain wetness hooks + fog interaction.
Foundational for many games.

**Non-goals**: realistic fluid simulation; ship/boat physics; underwater
caves (caves system covers that).

### Weather
Rain / snow / wind / accumulation. Visual effects + gameplay
hooks (slippery surfaces, reduced visibility). Builds on atmosphere
schema. **Climate input**: spec 22 currently provides three flat
scalars per biome (temperature / humidity / wind). A per-location
ClimateKernel (regional gating from elevation + latitude +
distance-from-water) is a Phase 11 deliverable inside the weather
sprint — it consumes terrain backend + spec 19 kernel infrastructure.
Until Phase 11, weather reads flat per-biome climate; mountaintop +
valley share temperature. (Outside-audit OA-S1 2026-05-17: previously
this section claimed the kernel as if implemented; corrected to
deferred.)

**Non-goals**: long-term seasonal cycles (covered by climate via
configuration, not runtime simulation); tornados / hurricanes / extreme
events (out of v0 scope; could be Tier 4).

### Caves / interiors
SDF-carved volumes into the heightfield. Marching-cubes / surface-nets
mesh extraction. Dual-mat blend at cave/surface interface. No loading
screens — caves are part of the streamed chunks. Phase A (caves) →
Phase B (small buildings) → Phase C (castles / multi-building) per
W4.1 wishlist.

**Non-goals**: dynamic cave editing in runtime (deferred); cave
lighting beyond Tier 1 lighting; cave-specific AI (consumer concern).

### Runtime terrain deformation
Player or event-caused heightfield edits at runtime (craters, footprints,
explosions). Impact subtracts a crater profile from the chunk's
heightmap, mesh rebuilds via Job system, splat gets a "disturbed earth"
or scorch decal painted. Touches change-broadcast for nav/decor
invalidation.

**Non-goals**: deformation persistence (handled by persistence system);
deformation by terrain-altering spells (consumer territory using the
deformation API).

### Persistence + author overrides
"Replace procedural with handcrafted" pattern across all systems.
Stored edits: placed objects, overridden chunks, authored POIs,
modified biome masks, roads, gameplay markers. Schema includes
authored-data hash for cache invalidation. Save / load contract.

**Non-goals**: multiplayer state sync (consumer); save-game UI
(consumer); cross-session collaborative editing (not in scope).

### Impostors
Distant-tier LOD for decoration (2 crossed billboards + alpha PNG +
basic normal). Reuses texture pipeline for the alpha cutouts. Works
for trees, plants, rocks, crystals, totems, distant signs — any
roughly cylindrically-symmetric subject. Standard AAA technique.

**Non-goals**: octahedral impostors (parked); animated impostors;
hero-quality impostor authoring tools.

### Roads / paths / corridors
Procedural path contract that can later accept hand-authored
roads/trails. Cuts through terrain, modifies splat, blocks decoration
along its width. Optional surface (gravel / cobblestone / dirt) per
biome. Tier 2 because games need intentional traversal, not just
terrain.

**Non-goals**: full city / town layout (consumer territory); navmesh
generation along roads (handled by nav export).

---

## Tier 3 — Output / packaging

### Bake recipes
Offline tools that render the W5 world to:
- **2.5D bake**: side-on or iso, painterly post-process
- **Topdown bake**: cartographic / map style
- **World map bake**: low-detail strategic-scale image

Each runs as a Python pipeline tool that loads a world bundle, renders
via Godot in headless mode, saves PNGs + JSON manifest. Consumer
projects (e.g. 2D wizard game) pull in baked artifacts.

**Non-goals**: realtime 2.5D / topdown at game runtime; bake-time
gameplay logic (just rendering).

### Plugin packaging + versioning
W5 ships as a Godot addon. `engine/plugin.cfg` is the manifest.
Semver. `engine/` has a stable public API; internals marked. Consumer
projects install via standard Godot addon install (or git submodule).
Bake outputs (worlds, baked images, etc.) carry a `w5_version` stamp
for migration.

**Non-goals**: realtime plugin hot-reload; cross-Godot-version
compatibility (we pin to Godot 4.5+).

### Consumer demo
The `demo/` Godot project that USES the W5 addon end-to-end. Walks
through one biome, then the two-biome target. Validates that the
addon actually works as an addon (not just "we have an engine subdir").
Also serves as the documentation-by-example for consumers.

**Non-goals**: shipping `demo/` as a game; demo-only features.

### Forkability validation
The structural test of the success metric. Take W5, fork into 2-3
independent demo projects, see what breaks. Document install steps.
Fix breakage. Run again until clean.

**Non-goals**: validation of every possible consumer use case (sample
3); maintaining the forks long-term.

---

## Tier 4 — Decided (scope decisions from 2026-05-16 review)

These were Tier-4 open items in the original inventory; decided now.

### Animals / NPCs — OUT
Consumer responsibility. Engine ships decoration + foliage; consumer
handles NPCs / wildlife / monsters. Keeps engine scope tight.

### Audio — HOOKS ONLY
Engine exports an audio-tag manifest per biome/zone/decoration; consumer
wires actual `.ogg`/`.wav` files. **Engine ships zero audio assets.**
The audio-hooks spec is a Tier 1 contract (audio is substrate-level
even if engine doesn't ship sounds).

### LLM-drivability — PROPERTY OF EVERY SYSTEM
Not a separate productized system. Every spec template requires a
"Discoverability" section: schema, validator, deterministic output,
machine-readable API, entry-point, minimal example. Same docs serve
humans + LLMs alike. Enforced via spec template (see
`docs/specs/00_SPEC_TEMPLATE.md`).

### Climate kernel — FOLDED INTO WEATHER (probably)
Folds into the Weather system spec rather than being separate. Decide
during weather spec authoring.

### Auto-biome from DEM features — IN
Procedural biome assignment is the default for new worlds. Spec under
Materials / Biome catalog. Hand-authored splats remain as an override
path for hand-set-piece worlds.

### Erosion (heightmap pre-process) — IN
Hydraulic + thermal erosion at chunk generation. Spec under Terrain
backend.

### Ground variety architecture — BLOCKED on renderer sprint
Per audit (2026-05-16, finding C2): the variety architecture is
renderer-coupled and cannot be pre-committed before spec 15a (renderer
decision) lands. Five candidates live in spec 24 (virtual texturing,
detail texture array, siblings + stochastic UV, building-block
compositor, multi-frequency triplanar). Previous inventory pre-commit
("siblings + stochastic UV first") retracted; the decision waits for
the renderer sprint.

---

## What's NOT in W5 (explicit)

These were considered and cut:

- **Runtime view-mode switching (walk/iso/topdown)** — runtime is 3D
  only. 2.5D/topdown via offline bake recipes.
- **Multi-machine / distributed worldgen** — single-machine only.
- **Multiplayer state sync** — consumer concern.
- **Realtime fluid simulation** — water uses shaders + heuristics, not
  physics.
- **Ray tracing** — Godot 4.5 doesn't ship RT.
- **Texture authoring UI** — we generate, we don't paint.
- **Realtime tree-growth animation** — static foliage with wind shader,
  no growth.
- **Animals / NPCs / wildlife** — consumer responsibility. Engine
  ships decoration + foliage, not behaviored agents.
- **Audio assets** — engine ships hooks (tag manifest); consumer ships
  the actual sound files.
- **Productized "LLM agent wrapper" system** — LLM-drivability is a
  property of every system (schema + validator + deterministic output +
  example), not a separate product. Enforced via spec template.

---

## Revision history

- 2026-05-16: initial draft + same-day decision pass (Tier 4 resolved,
  Roads IN as Tier 2, Impostors own Tier 2, Animals OUT, Audio HOOKS
  only, LLM-drivability as property of every system, ground variety =
  siblings + stochastic UV first with compositor as deferred upgrade).
- 2026-05-16: post-audit. Retracted ground-variety pre-commit (C2);
  variety architecture is renderer-coupled and waits for spec 15a.
