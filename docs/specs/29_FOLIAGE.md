# Spec: Foliage System

> Status: draft
> Tier: 1 (core)
> Depends on: 26_TRELLIS_3D_PIPELINE, 25_TEXTURE_PIPELINE, 27_LOD_BAKE,
> 07_JOB_SYSTEM, 08_SPATIAL_INDEX, 09_ASYNC_ASSET_STREAMING,
> 10_STREAMING_BUDGET, 22_BIOME_CATALOG, 28_DECORATION, 40_IMPOSTORS
> Consumed by: terrain renderer (foliage rendered alongside terrain +
> decoration); world contract

## Purpose

W4.1's foliage gap closed. TRELLIS can't model branching topology —
trees + complex plants extract as fragmented mesh. W5 builds a
**parametric foliage system**: TRELLIS produces the trunk (which it
handles well — thick organic geometry); procedural rules produce
limbs / leaves / branches / variation per instance. Per-biome species
rules; wind shader; LOD chain ending in impostors (spec 40).

Per user direction (Block 4 of W5 plan): "trunk + tileable bark +
figure out procedural limbs/leaves/branches/height/width." This spec
defines the full system; the implementation is multi-phase but the
ARCHITECTURE is locked from the start.

This is the **largest single Tier 1 system in W5** by implementation
cost. Plan-doc time alone will need its own session. Pillar 4 says
no time constraint; the work scope is real and committed.

## Non-goals

- Realtime tree growth animation (static species, instance-level
  variation only)
- Hand-authored individual trees (we ship rules + per-biome libraries;
  consumers tune via config)
- Photoreal species accuracy (stylized fine — matches W5 overall art
  direction)
- Tree felling / damage / dynamic state (consumer territory; W5
  optionally publishes change_broadcast events for it)
- Underwater kelp / coral / etc. (sea-floor decoration is a future
  spec under water spec 35 if scoped)

## Architecture (full system, committed)

```
┌──────────────────────────────────────────────────────────────┐
│ PIPELINE (Python, offline; pipeline/foliage/)                │
│                                                               │
│  [1] Trunk generation                                         │
│      • TRELLIS produces hero trunk mesh per species           │
│        (call into spec 26 with trunk-shaped input image)      │
│      • Hand-curated input images per species (~20-50 species  │
│        in W5 v1; ~3-5 per biome)                              │
│      • Output: trunk_<species>.glb at 4-8K tris               │
│                                                               │
│  [2] Bark texture (tileable)                                  │
│      • Texture pipeline (spec 25) generates tileable bark     │
│        per species (1-3 variants for sibling-variety)         │
│      • Applied to trunk + procedural branches                 │
│                                                               │
│  [3] Branch generator (NEW W5 module)                         │
│      • Parametric rules per species: trunk_height_range,      │
│        branch_count_range, branch_angle_range,                │
│        branch_taper_curve, etc.                               │
│      • Builds branch hierarchy as game-ready mesh             │
│      • L-system or recursive-rule based (TBD in plan doc)     │
│      • Reuses trunk's bark UV for continuity                  │
│                                                               │
│  [4] Leaf / needle cards                                      │
│      • Alpha-cutout PNGs of leaf clusters (deciduous) or      │
│        needles (conifer) generated via texture pipeline       │
│      • Texture pipeline's --subject mode (single-subject      │
│        alpha-cutout) — uses simple threshold alpha, NOT SAM   │
│      • Placed at branch tips per per-species placement rules  │
│      • Billboarded OR oriented to branch normal               │
│                                                               │
│  [5] Per-instance variation                                   │
│      • Same species rules → different specific tree per       │
│        instance via per-instance seed                         │
│      • Variation axes: trunk_lean, height_mult,               │
│        branch_seed, foliage_density, color_tint               │
│      • Variation is GENERATED into the mesh at instance       │
│        bake time — NOT runtime (consistent + perf-friendly)   │
│                                                               │
│  [6] LOD chain bake                                           │
│      • LOD0 hero: full geo (~20k tris, real leaf-card density)│
│      • LOD1 mid: simplified trunk + cluster billboards (~5k)  │
│      • LOD2 low: low-poly trunk + single canopy billboard     │
│      • Distant: spec 40 (2 crossed billboards via texture     │
│        pipeline alpha-cutout)                                 │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│ RUNTIME (GDScript; engine/scripts/foliage/)                   │
│                                                               │
│  • FoliageWorld scene component                               │
│  • Per-biome species placement (Poisson + biome/slope/        │
│    moisture gates, like decoration but separate path)         │
│  • Wind shader: per-vertex wind_factor, time-driven sway      │
│  • Per-instance random rotation + scale variation             │
│  • LOD selection per-instance with hysteresis + dither        │
│    (same pattern as decoration spec 28)                       │
│  • Streaming budget participation                             │
└──────────────────────────────────────────────────────────────┘
```

## V1 species scope

For the 2-biome demo:
- **Alpine biome**: ~3-5 species (spruce, pine, dead trunk, alpine
  shrub, etc.)
- **Wetland biome**: ~3-5 species (deciduous mixed, swamp tree, cypress
  /mangrove-like, reed cluster, etc.)

Total: ~6-10 unique species shipping in v1, each with 1-3 sibling
variants for variety. Per-instance variation provides additional
within-species variety.

## Per-biome rules

In `worlds/<world>/biome_decoration/<biome>_foliage.yaml`:

```yaml
biome: alpine
species:
  - id: pine_01
    density_per_m2: 0.008
    height_range_m: [4.0, 12.0]
    biome_weight_threshold: 0.5
    elevation_range_m: [800, 1400]
    slope_range_deg: [0, 45]
    cluster:
      mode: clump
      members_per: [2, 6]
      radius_m: [3.0, 8.0]
    variation:
      lean_max_deg: 8
      height_mult_range: [0.85, 1.15]
      foliage_density_range: [0.7, 1.0]
    wind:
      strength: 0.6
      frequency_hz: 0.4
```

Schema-validated. World contract (spec 14) enforces.

## Wind shader

Per-vertex `wind_factor` attribute (0..1) baked into the mesh during
foliage generation. Higher near leaf tips, lower at trunk base.
Vertex shader animates: `vertex.xz += wind_dir * wind_factor *
sin(time * frequency + per_instance_phase) * strength`.

Wind strength + direction are world-anchored uniforms (atmosphere/
weather system drives them). Per-instance phase offset prevents
synchronized swaying.

## Per-instance variation cost

V1 ships PRE-BAKED variation: at generator time, each species
produces N variant meshes (e.g. 8 baked variations of pine_01 with
different trunk leans, heights, branch seeds). Runtime picks one
variant per instance.

Future optimization (deferred): variation via vertex shader (per-
instance custom_data drives trunk push / branch angle). Removes the
N-variant overhead but adds shader complexity. Defer until measured.

## Phased implementation order

The architecture is locked; build order goes:

1. **Phase A — Trunk pipeline only.** TRELLIS trunks + tileable bark.
   Produces visible-but-dead trunks. ~3 sessions.
2. **Phase B — Procedural branches.** Branch generator module + bark
   continuity. Trees now have geometry. ~5-7 sessions.
3. **Phase C — Leaf cards.** Alpha-cutout leaf clusters at branch
   tips. Trees look like trees. ~3-5 sessions.
4. **Phase D — Per-instance variation.** Baked variants per species.
   Forest no longer reads as clones. ~2-3 sessions.
5. **Phase E — Wind shader.** Trees sway. ~2 sessions.
6. **Phase F — LOD chain bake (hero/mid/low).** Distance falloff.
   ~3-5 sessions.
7. **Phase G — Per-biome rules + runtime placement.** Trees show up
   in the right places. ~3-5 sessions.
8. **Phase H — Impostor handoff (spec 40).** Distant trees render as
   billboards. ~2-3 sessions (spec 40 owns the impostor system; this
   spec owns the foliage-side LOD2-to-impostor transition).

**Author estimate: ~25-35 sessions.**
**Outside-audit re-estimate (S1, 2026-05-16): ~60-100 sessions.**

The audit (rightly) flagged this as the most-optimistic estimate in
the whole spec set. Parametric branch generation is a graduate-thesis-
scale problem; even with FLUX + TRELLIS doing the leaf/bark/trunk
work, getting "good looking trees" across 6-10 species via L-systems
or space-colonization is real algorithm tuning work.

Pillar 4 (no deadline) protects against shipping bad foliage. Both
estimates stand; treat 60-100 as the planning number and 25-35 as
the floor if everything goes right. Largest single Tier 1 system in
W5 regardless of which estimate wins.

## Public API (skeleton)

```gdscript
# engine/scenes/components/foliage_world.tscn
class_name FoliageWorld extends Node3D

@export var world_bundle_path: String
@export var focus_camera_path: NodePath
@export var quality_tier_override: String = ""

signal forest_loaded()
func get_resident_tree_count() -> int
func get_visible_instance_count() -> int
```

```python
# pipeline/foliage/generate_species.py
python -m world5.foliage.generate_species --species pine_01 --biome alpine

# pipeline/foliage/bake_lod_chain.py
python -m world5.foliage.bake_lod_chain --species pine_01
```

## Producer / consumer contract

- **Produces** (pipeline): per-species geometry library (trunk +
  branches + leaves) + N baked variants per species + LOD chain
- **Produces** (runtime): rendered tree instances; wind shader
  uniforms published; streaming budget publish
- **Consumes**: biome catalog (per-biome species rules), TRELLIS
  output (trunks), texture pipeline (bark + leaves), LOD bake
  (decoration meshes if foliage shares some assets)

## Dependencies

- `26_TRELLIS_3D_PIPELINE` (trunks)
- `25_TEXTURE_PIPELINE` (bark + leaves)
- `27_LOD_BAKE` (only for non-foliage decoration that share the same
  asset library; foliage has its own LOD bake path)
- `07_JOB_SYSTEM`, `08_SPATIAL_INDEX`, `09_ASYNC_ASSET_STREAMING`,
  `10_STREAMING_BUDGET`, `11_CHANGE_BROADCAST` (Tier 0 primitives)
- `22_BIOME_CATALOG` (per-biome species rules)
- `28_DECORATION` (vertical layering coordination — foliage canopy
  layer must coexist with decoration's floor/understory)
- `40_IMPOSTORS` (distant-tier rendering)

## Quality bar

- **Visual**: forest reads as forest, not clones (per-instance
  variation cap on visible repetition); foliage moves naturally
  in wind; no visible LOD pops (dither handles it)
- **Performance**: foliage (geometry + wind shader + LOD pass)
  combined ≤ 0.8 ms per frame at `high` tier (authorized by
  `X_FRAME_BUDGET.md`); 1000-instance forest at 60fps p99 on RTX 3060
  with LOD chain + impostors active
- **Authoring cost**: new species ships ~2 sessions of work after
  v1 pipeline is built
- **Per-biome content**: v1 ships 6-10 unique species + variants
  serving 2 biomes

## Discoverability

- **Entry point**: `python -m world5.foliage.generate_species`
  (pipeline); `FoliageWorld` scene component (runtime)
- **Schema**: per-species YAML schema + per-biome foliage YAML
  schema, both in `engine/resources/schemas/foliage/`
- **Validator / preflight**: world contract validates species
  refs + biome rules
- **Example**: `engine/examples/foliage_example_world/` with one
  species
- **Deterministic outputs**: yes — same species rules + same seed +
  same variation params → same baked variant; same per-instance seed
  → same picked variant at runtime

## Open questions

- **Branch generator algorithm**: L-systems (classic) vs recursive
  rules (simpler) vs space-colonization. Defer to Phase B plan doc.
- **Leaf billboarding vs oriented quads**: billboarded leaves always
  face camera (faster, less realistic at close range); oriented
  follow branch normals (more realistic, more geo). Per-species
  choice or per-tier? Defer to Phase C.
- **Cross-species sibling pool**: can pine_01 and pine_02 share
  bark texture (palette-locked)? Probably yes; reduces texture
  budget. Defer to Phase A authoring.
- **Foliage placement: own system or part of decoration?**: RESOLVED
  (audit S8). Foliage runs its OWN placement using shared spatial
  index (spec 08) and shared `placement_exclusion` broadcast on
  ChangeBroadcast (spec 11). Foliage publishes trunk footprints as
  exclusion zones; decoration subscribes and skips its scatter
  within them, and vice versa for large decoration structures.
  Vertical layering still applies for canopy non-foliage items
  (hanging moss, vines).
- **Dead trees / fallen logs**: spec'd as "dead trunk" species (no
  leaves, leaning lean_max_deg high). Decoration system could also
  handle as a regular subject. Probably decoration; foliage system
  is for living-tree-shape species.

## References

- W4 plan 08 (foliage pipeline; speced but never built)
- WISHLIST "Vegetation + organic-asset system" (long-form vision)
- L-systems literature (Lindenmayer; classic tree generation)
- SpeedTree feature reference (what AAA expects from foliage)

## Revision history

- 2026-05-16: initial draft
