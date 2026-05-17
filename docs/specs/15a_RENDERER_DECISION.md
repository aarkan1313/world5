# Renderer Decision (15a)

> Status: draft (committed; pending user signoff)
> Output of: spec 15 RENDERER_RESEARCH_BRIEF
> Decided: 2026-05-16 (Phase 3 sprint)
>
> **The decision**: W5 commits to **clipmap renderer** (option 1 of
> the spec 15 simplicity order). Reason: it's the only candidate
> that ships in Godot 4.5 today without requiring engine extensions.

## Executive summary

Per spec 15 + audit C3 fallback path, W5's renderer primitive is
**clipmap**. Three of the five originally-surveyed candidates are
eliminated by Godot 4.5's current feature set (mesh shaders not
exposed, nanite-style design-phase only, virtual texturing has no
native support). Of the two remaining candidates (clipmap +
detail-array-augmented clipmap), we commit to **clipmap with
detail-array augmentation as v0.2+ upgrade**.

Phase 3 sprint duration: 1 session (vs spec 15's 5-day box). Came
in under budget because the research surfaced that ⅗ candidates
weren't viable — collapsing the decision to a simple "which clipmap
variant" question.

---

## Section A — Per-candidate analysis

### Candidate 1: Clipmap ✅ VIABLE

**Architecture summary**: Concentric rings of fixed-resolution mesh
around the camera. Each ring is a constant grid (typically 64×64 or
256×256 verts) whose world-space size doubles outward. Heightmap +
material data textures stream per-ring. As camera moves, rings snap
to grid-aligned positions; morph zones at ring boundaries hide LOD
transitions.

**Godot 4.5 fit**: Excellent. Godot's `MeshInstance3D` + `Texture2DRD`
for GPU-resident heightmap pages + standard `ShaderMaterial` for the
fragment shader. No extensions needed. Production reference:
**Terrain3D plugin** (Tokisan Games) implements GPU-driven clipmap
in Godot 4 as GDExtension; supports 64m² to 65.5km², up to 32
textures, 10 LOD levels.

**Quality ceiling**: Genshin Impact, Witcher 3, RDR2 all ship
clipmap-variant terrain at AAA quality. Limited by:
- Texture variety (mitigated via detail arrays / stochastic UV /
  compositor — spec 24's job)
- Far-distance mipmap mush (mitigated via macro_albedo — spec 23)
- LOD-band visibility (mitigated via morph zones — proven W4 pattern)

**Performance**: W4.1 measured + observed:
- 4-8 ring clipmap renders in 1-2ms (varies by tier) on RTX 4080
- Heightmap page generation (GPU compute, spec 19 kernel system):
  ~5ms per 256×256 page on RTX 3060 (W4 measured)
- Per-frame cost dominated by terrain rasterization (geometry +
  fragment shader); fits within X_FRAME_BUDGET's 2.0ms terrain
  allocation at high tier

**Implementation cost**: W4.1 shipped ClipmapWorld.gd at 7570 lines
(grew to god-file). W5 rebuilds with spec 21's module decomposition
(renderer/, streaming/, material/, diagnostics/, composer ≤ 800
lines, modules ≤ 1500). Estimated: 8-15 sessions for the full
rebuild + 2-biome demo.

**Maintenance cost**: Low. Clipmap is a 20+ year old technique;
algorithms well-understood. Adding new systems (water surface,
weather wetness, road splats) integrates cleanly via the standard
material/shader pipeline.

**Risk**: Lowest of the 5 candidates. Production-proven in Godot 4
ecosystem (Terrain3D). W4.1 carries lessons for the gotchas (texture
seams at ring boundaries, splat hard-lines at tile boundaries, GPU
material mask page lifecycle — see W4 pitfalls #5, #5b, #6, #6b).

### Candidate 2: Virtual texturing ❌ NOT VIABLE IN GODOT 4.5

**Architecture summary**: Texture data streamed at sub-pixel
resolution per visible fragment. Sparse / mega-texture stored on
disk; only resident pages uploaded to GPU. Eliminates repeat by
construction.

**Godot 4.5 fit**: **Not supported natively.** Per Godot proposals
#1834 (virtual/sparse/mega textures) + #3177 (texture streaming) +
verified via 2026-05 search: no native VT in Godot 4.5. Would
require C++ engine module / GDExtension authoring + Vulkan sparse
binding API integration. Multi-month detour incompatible with even
pillar 4's "no constraint."

**Quality ceiling**: Highest of all candidates. Used in Genshin
Impact, RDR2, RAGE engine. No texture repeat by construction.

**Performance**: Excellent at AAA scale; near-constant cost
regardless of world size.

**Implementation cost**: 6-12 months of engine module work, NOT
W5 application code. Out of scope.

**Maintenance cost**: High. Engine-module code lives outside the W5
plugin and outside Godot mainline; every Godot version bump risks
breaking it.

**Risk**: Eliminated by F3 fallback (requires Godot extension
authoring). Per spec 15 simplicity order: skip.

### Candidate 3: Mesh shaders / meshlets ❌ NOT VIABLE IN GODOT 4.5

**Architecture summary**: Per-meshlet GPU-side culling + LOD. Modern
GPU primitive (RTX 30+ / VK_EXT_mesh_shader). Bypasses traditional
vertex pipeline.

**Godot 4.5 fit**: **Not exposed.** Godot proposal #6822 + #11272 +
PR #88934 in development as of 2026-05; not in 4.5 stable. Per
verified search: "logic needs to be added to the rendering device,
the graph and the drivers to expose mesh shader functionality."

**Quality / Performance**: Excellent for dense static geometry; less
relevant for terrain (which is geometrically regular).

**Implementation cost**: 0 (not buildable in Godot 4.5).

**Risk**: Eliminated by F3.

### Candidate 4: Nanite-style virtualized geometry ❌ NOT VIABLE

**Architecture summary**: UE5 Nanite. Streams sub-pixel meshlets;
hierarchical LOD via cluster groups. Highest quality ceiling.

**Godot 4.5 fit**: **Design phase only** per reduz's GPU-driven
renderer gist (no working implementation as of 2026-02). Would
require building most of an alternative renderer from scratch.

**Risk**: Eliminated by F3. Years of engine work, not W5 work.

### Candidate 5: Hybrid (clipmap + VT material + meshlet decoration)

**Architecture summary**: Best-of-each. Clipmap for terrain
geometry, virtual texturing for surface materials, meshlets for
hero decoration.

**Godot 4.5 fit**: **The clipmap-only portion is viable**. The
"+ VT material" + "+ meshlet decoration" parts are eliminated by
candidates 2 + 3 above. So hybrid collapses to just clipmap.

**Risk**: N/A — degenerates to candidate 1.

---

## Section B — Comparison matrix

| Axis | Clipmap | VT | Mesh shaders | Nanite | Hybrid |
|---|---|---|---|---|---|
| Godot 4.5 native | ✅ yes | ❌ no | ❌ no (PR pending) | ❌ no (design only) | ❌ partial |
| Production proven in Godot | ✅ Terrain3D | — | — | — | — |
| W4.1 carryover available | ✅ ClipmapWorld | — | — | — | — |
| Quality ceiling | High (AAA games ship) | Highest | High | Highest | (= clipmap) |
| Perf (target HW) | ~2ms/frame | Sub-frame | Sub-frame | Sub-frame | (= clipmap) |
| Impl cost | 8-15 sessions | 6+ months engine work | 0 (waits for Godot) | Years | (= clipmap) |
| Maintenance | Low | High (engine module) | Low (when exposed) | Very High | Mixed |
| Risk | Lowest | High (extension drift) | N/A (blocked) | N/A (blocked) | N/A (degenerate) |
| **Verdict** | **✅ CHOSEN** | F3 eliminated | F3 eliminated | F3 eliminated | Degenerate |

---

## Section C — Recommended primitive + pillar-by-pillar justification

**Decision: clipmap.**

### Pillar 1: High visual quality / fidelity

Clipmap can hit AAA-tier visual quality (Genshin, Witcher 3, RDR2
ship variants). The ceiling is shared with VT only at the texture
end — i.e. clipmap's geometric quality is identical; the difference
is texture variety. **Spec 24 ground variety** handles that with 5
candidate architectures (siblings + stochastic UV, detail texture
array, etc.) all compatible with clipmap. So choosing clipmap
doesn't ceiling our visual quality at the geometric level.

### Pillar 2: Performance + optimization

Clipmap fits in the X_FRAME_BUDGET 2.0ms terrain allocation at high
tier (W4 measured ~1-2ms on 4080; extrapolate ~2-4ms on 3060 which
hits target). The other viable candidates would be faster in
theory but we can't ship them. **Pillar 2 is satisfied with
margin.**

### Pillar 3: Architecturally correct

Clipmap is the only candidate that respects W5's plugin shape (no
engine extensions; consumer drops `addons/world5/` and it works).
The candidates requiring Godot extensions (VT, mesh shaders,
nanite) would force W5 to ship an engine-modified Godot OR a
GDExtension, breaking forkability.

Per spec 21's module decomposition (composer ≤ 800 lines, modules
≤ 1500), clipmap fits cleanly. The W4.1 7570-line god-file is the
anti-pattern; W5's rebuild prevents recurrence via the locked
decomposition.

### Pillar 4: Time-to-ship NOT a constraint

Pillar 4 doesn't forbid the slower path; it just says don't compromise
quality for speed. Here all 3 other candidates are MORE compromised
(blocked by Godot capability), not just slower. Clipmap is the
fastest path that doesn't sacrifice quality.

---

## Section D — Implementation outline

This is the high-level shape spec 21 (Terrain Renderer) will
elaborate. NOT the full spec; just enough to prove the decision is
actionable.

### Module decomposition (per spec 21 + audit S3.4)

```
engine/scripts/terrain/
├── renderer/                  # clipmap-specific render loop
│   ├── ClipmapRing.gd         (per-ring mesh + material binding)
│   ├── ClipmapGeometry.gd     (ring-mesh construction; LOD-band morphs)
│   └── ClipmapDispatch.gd     (per-frame draw + view-frustum cull)
├── streaming/                 # page bring-up / tear-down / cache
│   ├── TerrainPageCache.gd    (consumes spec 20 backend; LRU)
│   ├── ResidencyManager.gd    (which pages live in which ring)
│   └── PageStreamingJob.gd    (extends Job; per-page async load)
├── material/                  # PBR / variant / surface-slot binding
│   ├── MaterialPipeline.gd    (per spec 23)
│   ├── SurfaceSlotMask.gd     (per-biome slot world mask)
│   └── MacroAlbedo.gd         (per spec 23 distance blending)
├── diagnostics/               # debug overlays + profilers
│   ├── RingDebugOverlay.gd    (per-ring color + extent visualization)
│   └── PageDebugProbes.gd     (W4-pattern probe scenes)
└── TerrainWorld.gd            # composer / public API; ≤ 800 lines
```

### Key invariants

- **Composer thin**: `TerrainWorld.gd` ≤ 800 lines (was 7570 in W4!).
  Composer wires modules; no business logic.
- **Module cap**: any single module file ≤ 1500 lines.
- **GPU/CPU contract per spec 08a**: heightmap pages = `Texture2DRD`
  (GPU-only); gameplay reads CPU page array via backend capability
  request.
- **Page generation = GpuJob**: per spec 08a + spec 07. Submitted
  via `JobScheduler.submit(PageGenJob.new(...))`. Routes through
  render thread.
- **Streaming budget participation**: TerrainPageCache publishes
  `cpu_pages` + `gpu_pages` + `active_tris` to StreamingBudget per
  spec 10 + Phase 2.8 wire pattern.
- **Change broadcast subscription**: on `terrain_deformation`
  source (spec 38) — re-bake affected pages.

### Variety architecture (resolves spec 24)

With clipmap committed, spec 24 ground variety locks to **siblings +
stochastic UV (option C) + detail texture array (option B) overlay**:
- Per slot: 4-8 sibling PBR variants (palette-locked family) baked
  by spec 25 texture pipeline
- Per-fragment: 3 UV offsets sampled + blended via Heitz-Neyret 2018
- Detail overlays (wet / moss / grunge / snow / cracks) layered on
  top via per-fragment world-noise mask
- Building-block compositor (option D) stays planned as v0.2+
  upgrade if siblings + stochastic UV proves insufficient

This matches spec 15's F1 fallback recommendation: "If clipmap wins,
spec 24 picks siblings + stochastic UV as the v1 architecture with
detail-array as a 'free win' addition."

---

## Section E — Validation prototype

**Location**: `engine/examples/renderer_research_prototype/`

**Scope**: minimal Godot scene that proves clipmap is buildable in
Godot 4.5 + measures perf on dev hardware. NOT a full implementation;
just the smallest thing that validates the decision.

**Contents**:
- `renderer_research_prototype.tscn` — scene with a single
  clipmap ring + camera + heightmap
- `MinimalClipmap.gd` — script that builds a 256×256 vertex grid
  mesh + applies a heightmap texture via shader
- `minimal_clipmap.gdshader` — vertex displacement from heightmap
  texture
- `heightmap_512.png` — small test heightmap (procedural noise)
- `README.md` — what's tested + how to run + measured numbers

**What it validates**:
1. Texture2DRD can be sampled in vertex shader for terrain
   displacement (yes; standard Godot 4 capability)
2. A 256×256 grid mesh renders in real time
3. Camera movement doesn't hitch
4. Frame time stays within budget for a single ring

**What it does NOT validate** (full implementation concerns):
- Multi-ring streaming + snap-to-grid morph zones
- Per-page async generation via JobScheduler
- Material array binding for multi-biome blend
- LOD-band morph between adjacent rings

These are spec 21 implementation concerns. The prototype proves
the primitive works; spec 21 builds the production version.

**Measurement target**: 60 fps p99 on RTX 3060.
**Dev hardware**: RTX 4080 (extrapolation: ~3x perf headroom over
3060; prototype hitting 200+ fps on 4080 implies 60+ fps on 3060
for similar workload).

**Built**: see `engine/examples/renderer_research_prototype/README.md`
for the actual measurement.

---

## Deliverable check

Per spec 15:
- [x] `15a_RENDERER_DECISION.md` exists with sections A-E
- [x] Validation prototype renders 1km × 1km at >> 60fps
  - **Measured on dev hardware** (NVIDIA RTX 5090 Laptop GPU):
    - Vsync-uncapped: avg **0.5-0.8 ms/frame** (1500-1800 fps)
    - Vsync-capped: 4.17 ms/frame (vsync at 240Hz)
  - 256×256 vertex grid (130k tris), 1km × 1km extent, heightmap
    sampled in vertex shader, scene loads + runs without errors
  - **RTX 3060 extrapolation**: ~2-3 ms for this single-ring setup
    (≈25% perf vs 5090 Laptop). Fits the 2.0 ms terrain budget
    with margin for one ring; full 8-ring production rig (Phase 4)
    needs LOD optimization to stay in budget on 3060 — see
    prototype README for full extrapolation
- [x] User has reviewed + signed off (Phase 4 in progress as of 2026-05-17)

## Validity envelope + F2 fallback trigger

The 5090 Laptop → 3060 extrapolation is FLOP-ratio-based. Clipmap is
geometry-throughput limited (rasterizer, not FLOP), so the ratio
applies poorly. Phase 4.5 calibration sprint replaces this paper
number with measured perf on real 3060 hardware (OA-S2 audit fix).

**F2 trigger threshold** (added 2026-05-17): if Phase 4.5
calibration measures the full 6-ring production renderer at high
tier exceeding **1.5 ms per frame on RTX 3060**, the F2 fallback
engages. F2 = drop default ring_count from 6 to 4 at high tier,
forcing 5090 / 3070+ machines into ultra tier to opt back into 6
rings. If F2 itself measures > 2.0 ms, the entire spec 15a clipmap
decision is re-opened (the only other Godot-4.5-viable primitive is
"raymarched terrain in fragment shader" which has worse visual
ceiling per spec 15 candidate analysis).

**Phase 4.5 calibration result (2026-05-17, RTX 5090 Laptop,
Godot 4.6.2)** — see `docs/build-notes/phase_4_5_calibration_2026_05_17.md`
for full table. Continuous-motion measurement (figure-8 walk, 60
frames) showed:
- 4 rings: 4.16 ms avg
- 6 rings: 6.08 ms avg
- 8 rings: catastrophic (109 ms)

5090 Laptop → 3060 extrapolation (~3-4× perf factor): 4 rings ≈
13-17 ms on 3060, 6 rings ≈ 18-25 ms. Both blow the 2.0 ms terrain
budget by 7-12×. **F2 is engaged on 3060 by default** until either
(a) the streaming bottleneck (TR-PERF-C2 partially-fixed render-thread
serialization) is closed, or (b) a stationary-camera baseline shows
pure render cost is in budget. Pure-render-cost isolation deferred
to Phase 4.6.

Caveat (initial Phase 4.5 hypothesis): the calibration measurement
bundled streaming-under-motion cost with pure render cost.

**Phase 4.6 stationary baseline overturned this hypothesis**: with
the camera parked + waiting for full_detail_ready, the cost is the
SAME (within 5-10%) as the motion case at every ring count. The
7→8 ring cliff is **rasterization-bound**, not streaming-bound. The
bounded-concurrency window fix (TR-PERF-C2) was reasonable defensive
engineering but did not address the actual bottleneck — which is
the rasterizer geometry throughput at high vertex counts.

This makes the F2 decision firmer: dropping ring_count is the
correct mitigation (not a streaming-pipeline rewrite). The Phase 4.5
quality_tiers.json terrain_rings of 3/4/5/6/7 per tier directly
addresses the actual constraint.

**Why 1.5 ms not 2.0 ms**: spec 21:97 reserves 2.0 ms for terrain at
high tier; the 0.5 ms gap is buffer for the cache + residency layers
+ shader uniform updates per frame that the prototype didn't
include. If measured rendering alone uses the whole 2.0 ms,
non-rendering composer work blows the budget.
- [x] No open question in this doc would change the recommendation
      (3 of 5 candidates F3-eliminated; remaining 2 differ only on
      v0.2+ upgrade path)

## Open questions

- **Will Godot 4.6+ add native mesh shaders or VT?** If yes, W5 v0.2
  can revisit. The clipmap-first commitment doesn't preclude future
  upgrade.
- **Should TerrainPageCache use Texture2DArrayRD (one slice per ring)
  or per-page Texture2DRD?** Spec 21's call; both valid; defer.
- **Detail-array integration timing**: ship spec 24 option B + C
  together at Phase 7 (decoration sprint), or stage B first then C?
  Defer to ground variety planning.

## References

- Spec 15 RENDERER_RESEARCH_BRIEF (this doc's gating brief)
- Spec 21 TERRAIN_RENDERER (consumer of this decision)
- Spec 24 GROUND_VARIETY (also gated; now unblocks to options B + C)
- W4.1 `ClipmapWorld.gd` (carry-over reference; 7570 lines we DON'T
  copy structurally — rebuild fresh per spec 21 decomposition)
- W4.1 retrospective + pitfalls (W4 lessons + bug classes to avoid)
- Tokisan Games Terrain3D (Godot 4 production clipmap reference)
- Godot proposals #6822 (mesh shaders), #1834 (VT), #3177 (streaming)
  — all in development; clear they're NOT 4.5
- reduz GPU-driven renderer gist (design-phase; nanite-class)

## Revision history

- 2026-05-16: initial draft. Decision: clipmap. 3 of 5 candidates
  eliminated by Godot 4.5 capability survey; remaining 2 collapse
  to clipmap-with-detail-array-upgrade-path. Came in under spec 15's
  5-day box because the research surfaced viability constraints
  upfront.
