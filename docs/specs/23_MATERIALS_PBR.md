# Spec: Materials + PBR Pipeline

> Status: draft
> Tier: 1 (core)
> Depends on: 22_BIOME_CATALOG, 21_TERRAIN_RENDERER, 13_QUALITY_TIERS
> Consumed by: terrain renderer (material binding); ground variety system (spec 24); world contract

## Purpose

The runtime-side material system: per-biome PBR kits, surface slot
blending (slope + elevation + noise → slot weight), multi-biome
blending (splat weights from biome catalog → texture mix), bound as
`Texture2DArray`s for shader sampling.

Separate from the texture *pipeline* (spec 25, which produces the
textures). This spec is "what shape do they take + how do they
render."

W4.1 had this in `terrain_world_v3.gdshader` (~760 lines) tangled
with the renderer. W5 splits it into its own module under
`engine/scripts/terrain/material/` per the renderer module
decomposition (spec 21).

## Non-goals

- Texture generation (that's spec 25, texture pipeline)
- Ground variety / anti-repetition (that's spec 24, ground variety)
- Per-instance decoration materials (decoration runtime owns those)
- Material authoring UI (configs only)

## PBR kit shape

One kit per (biome × surface_slot). Lives at
`worlds/<world>/materials/biome_<biome>/<slot>/`:

```
materials/biome_alpine/
├── ground/
│   ├── albedo.png         (REQUIRED)
│   ├── normal.png         (REQUIRED)
│   ├── roughness.png      (REQUIRED)
│   ├── ao.png             (optional, defaults to white)
│   ├── macro_albedo.png   (REQUIRED for any world configured with
│   │                        visibility_ship_distance_m > 2km at any
│   │                        tier the world ships at;
│   │                        OPTIONAL otherwise — SA-S3.7 supersedes
│   │                        original M3 fix)
│   └── height.png         (optional, parallax mapping; expensive)
├── mid/
│   └── ... same map set
└── rock/
    └── ... same map set
```

Per-tier resolution: high tier expects 2048², ultra 4096², low 1024².
World contract enforces sizes per tier.

## Surface slot model

Each biome declares its slot list in the catalog (spec 22):

```json
"biome": {
  "name": "alpine",
  "surface_slots": [
    { "name": "ground", "weight": 1.0, "selector": "elevation < 800" },
    { "name": "mid",    "weight": 1.0, "selector": "slope_deg in [10,30]" },
    { "name": "rock",   "weight": 1.0, "selector": "slope_deg > 30 or elevation > 1000" },
    { "name": "snow",   "weight": 1.0, "selector": "elevation > 1200" }
  ]
}
```

Variable slot count per biome, 1-8 slots max (shader hard cap).
Selector rules use slope + elevation + noise to determine weight at
each fragment. Surface slot world mask (W4 pattern) bakes these into
a shared `Texture2DArrayRD` sampled at world XZ — same approach W4
proved works.

## Multi-biome blending

Biome catalog provides per-XZ biome weights (auto-biome + splat
overrides). Shader samples each active biome's slot textures and
blends weighted-sum.

Active biome cap: shader supports top-N biomes per fragment (N=4
typical; configurable per tier). Biomes beyond N get culled per
fragment to keep shader cost bounded.

## Macro albedo (distance blending)

When camera is far from a fragment, the high-frequency PBR detail
becomes mip-averaged and reads as mush. The macro_albedo companion
(at 256m world scale) blends in to give large-scale color variation
that survives mipmapping.

Optional but **strongly recommended for any world > 1km extent**.
W4 proved this is the single biggest readability lift for far-field
terrain.

## Public API (skeleton)

```gdscript
class_name MaterialPipeline extends Node

# Builds per-world material arrays at world-load time
func build_for_world(catalog: BiomeCatalog) -> MaterialBindings

# Runtime
class MaterialBindings:
    var pbr_array: Texture2DArrayRD       # [biome × slot × map_type]
    var macro_array: Texture2DArrayRD     # [biome × slot]
    var surface_slot_mask: Texture2DArrayRD  # [biome × slot] in world space
    var biome_splat_mask: Texture2DArrayRD  # [biome] in world space
    # ... etc
```

## Producer / consumer contract

- **Produces**: bound texture arrays + shader uniforms ready for
  terrain renderer
- **Consumes**: biome catalog (per-biome slot lists, material kit
  paths); validated PBR map files

## Dependencies

- `22_BIOME_CATALOG` (slot declarations + material kit paths)
- `21_TERRAIN_RENDERER` (consumer; material module lives under
  terrain/)
- `13_QUALITY_TIERS` (per-tier resolution, mipmap config, active
  biome cap)

## Quality bar

- Build for typical 2-biome world (8 PBR layers, 3 slots each) < 5s
- Per-fragment material sample cost (shader) fits within terrain's
  perf budget
- Visual quality: terrain reads as "good" at close, mid, and far
  distances — no mush at distance (macro_albedo), no plastic look
  (normal + roughness), no obvious texture repeats (handled by spec
  24 ground variety)
- Materials + ground variety shader pass: ≤ 0.8 ms combined per frame
  at `high` tier (authorized by `X_FRAME_BUDGET.md`); enforced via
  per-tier biome_cap + slot_cap limits (SA-S3.8)
- World contract catches: missing required maps, wrong-size maps,
  slot count > 8, missing macro_albedo when any configured tier's
  visibility_ship_distance_m > 2km (SA-S3.7)

## Discoverability

- **Entry point**: `MaterialPipeline.build_for_world(catalog)` at
  world load; resulting `MaterialBindings` passed to renderer
- **Schema**: PBR kit dir layout above; surface slot declarations in
  biome catalog spec 22
- **Validator / preflight**: world contract checks per-kit map
  presence + sizes
- **Example**: `engine/examples/material_kit_example/` shows a
  minimal valid kit
- **Deterministic outputs**: yes — same catalog + same kits → same
  bindings

## Open questions

- **Per-tier macro_albedo**: high tier might want 512m scale, low
  tier 128m. Defer per-tier tuning until renderer ships.
- **Triplanar projection for steep slopes**: cliff-side textures
  stretched along Y look bad. W4 didn't ship triplanar. Add to ground
  variety spec? Or here? Probably here, optional per-slot.
- **HDR PBR**: do we support HDR albedo (for emissive biomes — lava,
  glowing crystals)? Defer; SDR is fine for v1.

## References

- W4.1 `terrain_world_v3.gdshader` (~760 lines) — the source pattern;
  W5 splits material binding out from renderer
- W4.1 surface slot world mask (Stage 4.2 post-pass) — proven approach
- W4.1 macro_albedo companion (Stage 4.2af-ag) — readability win

## Revision history

- 2026-05-16: initial draft
