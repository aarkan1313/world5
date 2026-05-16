# Spec: Impostors

> Status: draft
> Tier: 2 (world)
> Depends on: 27_LOD_BAKE, 28_DECORATION, 29_FOLIAGE, 09_ASYNC_ASSET_STREAMING,
> 10_STREAMING_BUDGET
> Consumed by: decoration runtime + foliage runtime (distant-tier
> rendering swap from LOD2 → impostor at threshold distance)

## Purpose

Distant-tier rendering for decoration + foliage. Standard AAA
technique: **2 crossed billboards** sharing the vertical axis,
rotated 90° from each other. From any horizontal viewing angle,
at least one face is near-on (canopy visible) and one is near-edge-on
(gives the subject visible thickness).

Massively cheaper than LOD2 geometry at >200m: 4 triangles per
instance instead of ~500. A forest of 10,000 trees at distant tier
costs less than one hero tree.

V1 ships impostors for decoration (rocks, crystals, totems, distant
signs) and foliage (all tree species). Works for any cylindrically-
symmetric or mostly-distance-viewed subject.

## Non-goals

- Octahedral impostors (8-view sphere atlas; higher quality, more
  storage). Defer; 2-crossed is enough.
- Animated impostors (wind sway via shader yes; per-frame mesh swap
  no)
- Hero-quality impostor authoring tools (we automate)
- Front/back asymmetric subjects (statues, doors). Spec'd as
  out-of-scope per W4 wishlist; consumer uses LOD2 mesh at all
  distances if needed.

## V1 architecture

```
┌──────────────────────────────────────────────────┐
│ PIPELINE (Python, offline; pipeline/impostors/)  │
│                                                   │
│ [1] Per-subject impostor bake                     │
│     • Render LOD0 mesh at front orthographic     │
│       (Godot headless or Blender Cycles)         │
│     • Capture as RGBA PNG with alpha             │
│     • Optional: capture flat normal (points up)  │
│       for crude lighting                          │
│   ↓                                               │
│ [2] Atlas pack (optional, performance)           │
│     • Pack N species' impostor PNGs into one     │
│       atlas texture (default: per-species PNGs,  │
│       atlas as polish if measured)               │
│   ↓                                               │
│ [3] Output: <subject>/impostor.png + manifest    │
│                                                   │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│ RUNTIME (GDScript; engine/scripts/impostors/)    │
│                                                   │
│ • ImpostorMesh — 2-crossed-quad mesh primitive   │
│   per subject (4 tris, 8 verts, UV-mapped       │
│   to impostor PNG)                                │
│                                                   │
│ • Subscribed by DecorationManager + FoliageWorld │
│   at LOD3-distance threshold: instances that     │
│   cross the threshold swap from LOD2 mesh →      │
│   impostor MultiMesh                              │
│                                                   │
│ • One MultiMesh per (subject_id, impostor) bound │
│   to the impostor PNG; instances stamped with    │
│   y-axis rotation randomization for variety      │
└──────────────────────────────────────────────────┘
```

## Per-subject bake

For each subject in `subjects_3d/`:
1. Load LOD0 mesh
2. Set up Godot headless / Blender scene with front-facing ortho
   camera, distance such that the subject fills the framebuffer
3. Render with alpha (matte black background, alpha = mesh coverage)
4. Save as `subjects_3d/<category>/<name>/impostor.png` (RGBA;
   per-tier sizes: low 128, medium 256, high 512, ultra 1024,
   cinematic 2048)
5. Manifest update: `_impostor_meta.json` per subject (provenance +
   content address)

The bake is one-time per subject; cached via spec 12 content
addressing. Same LOD0 source → same impostor PNG → cache hit.

## Runtime mesh shape

Each impostor is a fixed 4-triangle mesh:
- Two quads, both with vertices at (-w/2, 0, 0), (w/2, 0, 0),
  (w/2, h, 0), (-w/2, h, 0)
- One quad rotated 90° around Y so the cross is visible from above

`w` and `h` derived from subject bounds (LOD0 bounding box width +
height; bake step records these in the manifest).

UV mapping: full PNG mapped to both quads (same texture sampled by
both). Per-instance random y-rotation in the MultiMesh gives variety.

## Lighting on impostors

Simple. Impostor PNGs are unlit-baked from the LOD0 (so they have
the "as rendered at LOD0" lighting baked in). Runtime adds:
- World-space directional fade to atmosphere ambient color
- Optional fog interaction (matches atmosphere fog uniforms)

Per-instance lit-from-side variation NOT supported in v1
(would need normal map; defer to octahedral impostor sprint if real).

## LOD swap threshold

Per quality tier:

| Tier | LOD2→Impostor swap distance |
|---|---|
| `low` | 80m |
| `medium` | 150m |
| `high` | 200m |
| `ultra` | 300m |
| `cinematic` | 500m |

Hysteresis applies (same pattern as per-instance LOD in spec 28):
swap-to-impostor at threshold; swap-back at threshold - 10m.

## Atlas (deferred)

V1 ships per-species PNGs (one impostor.png per subject). N
draw calls for N species visible. If measurement shows this
hurts perf (likely fine since impostor MultiMeshes consolidate
instances per-species), atlas-packing is a follow-up optimization.

## Public API

```python
# Offline bake
python -m world5.impostors.bake_all
python -m world5.impostors.bake_subject --subject rocks/boulder_01
```

```gdscript
# Runtime — used internally by decoration/foliage; not a top-level
# consumer-visible scene component (impostors are LOD-mode, not a
# system you instance)
class_name ImpostorMeshCache extends RefCounted
func get_impostor_mesh(subject_id: String) -> Mesh
```

## Producer / consumer contract

- **Produces**: per-subject impostor PNG + 4-tri mesh primitive +
  MultiMesh instances at runtime
- **Consumes**: LOD0 mesh from spec 27; decoration/foliage residency
  events from specs 28+29

## Dependencies

- `27_LOD_BAKE` (LOD0 source meshes)
- `28_DECORATION` (consumes impostor for distant decoration)
- `29_FOLIAGE` (consumes impostor for distant trees)
- `09_ASYNC_ASSET_STREAMING` (impostor PNG load)
- `10_STREAMING_BUDGET` (impostor draw calls + texture budget published)
- `12_CONTENT_ADDRESSING` (per-impostor cache key)

## Quality bar

- Per-subject bake: ≤ 30s (Godot headless render)
- Impostor PNG file size: ≤ 200KB per subject at 512×512
- Runtime impostor swap: hysteresis-protected; visually subtle
- Visual: forest at >200m reads as "lots of trees, distinct silhouettes";
  no obvious billboard-edge artifacts at 45° viewing angles
- 10,000-instance impostor forest: ≤ 0.2 ms per frame at `high` tier
  (authorized by `X_FRAME_BUDGET.md`); impostors are 4-tri batched
  MMI draws, designed-cheap. SA-S5.1 fix: prior "≤ 2 ms" was a
  pre-budget estimate; aligned to X_FRAME_BUDGET allocation.
- World contract validates impostor presence for any decoration/foliage
  subject that ships with declared distant rendering

## Discoverability

- **Entry point**: `python -m world5.impostors.bake_all` for offline;
  decoration/foliage runtime consume internally
- **Schema**: `_impostor_meta.json` shape (mirrors `_lod_meta.json`
  from spec 27)
- **Validator / preflight**: world contract checks impostor presence
  + correct sizing
- **Example**: `engine/examples/impostor_example.tscn` shows a
  forest of impostor trees at distance
- **Deterministic outputs**: yes — same LOD0 → same impostor PNG
  (Godot's headless renderer is GPU-deterministic given same inputs)

## Open questions

- **Bake renderer choice**: Godot headless vs Blender Cycles.
  Godot reuses the engine's renderer (consistent lighting); Blender
  has full bake control. Defer to plan doc; Godot probably wins.
- **Impostor for non-cylindrical subjects**: 2-crossed fails for
  wider-than-tall (fallen logs, sprawling vines). Spec'd as
  out-of-scope; consumer uses LOD2 mesh at all distances.
- **Dynamic lighting hint**: should runtime tint impostor by current
  atmosphere ambient + sun direction? Cheap; probably yes. Defer
  detail to plan.
- **Distance-fade-out**: at very-very-far (>1000m at cinematic),
  even impostors should cull entirely. Per-tier cull distance.

## References

- W4 WISHLIST "Vegetation impostor LOD pipeline" + "Distant-tier
  impostor generation pipeline"
- Standard AAA technique (used in Witcher 3, Horizon, RDR2 — every
  open-world game)

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-self-audit (SA-S5.1, SA-M5.2). Aligned 10k-instance
  perf bound to X_FRAME_BUDGET 0.2 ms allocation. Added per-tier
  texture sizes for ultra (1024) + cinematic (2048).
