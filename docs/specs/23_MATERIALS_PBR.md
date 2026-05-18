# Spec: Materials + PBR Pipeline

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — MaterialPipeline + per-fragment slot selection + biome_weights + PBR maps + triplanar hex sampler Phase 6)
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

### Sibling sets + detail overlays (Phase 5 amendment 2026-05-17)

Per-slot **sibling variants** live in a parallel directory next to
the base slot, named `<slot>_variants/`. Per spec 24 Layer 1
stochastic-UV blend:

```
biome_<biome>/
├── ground/
│   ├── albedo.png      (base — slot's "default" variant)
│   ├── normal.png
│   ├── roughness.png
│   └── ao.png
├── ground_variants/
│   ├── v0_albedo.png   (sibling 0 — different prompt, same palette family)
│   ├── v0_normal.png
│   ├── v0_roughness.png
│   ├── v0_ao.png
│   ├── v1_albedo.png   (sibling 1)
│   ├── v1_normal.png
│   ├── ...
│   └── v3_ao.png       (typically 4 siblings; max 8 per shader cap)
├── mid/
├── mid_variants/
├── rock/
└── rock_variants/
```

Per-biome **detail overlays** (spec 24 Layer 2) live at the biome
root in a `detail/` subdir, since detail tiles are biome-wide
(applicable across all slots), not slot-specific:

```
biome_<biome>/
├── detail/
│   ├── wet_albedo.png
│   ├── wet_normal.png
│   ├── wet_roughness.png
│   ├── moss_albedo.png
│   ├── moss_normal.png
│   ├── ...
│   └── (typically 5-7 detail tiles per biome)
└── (slot dirs as above)
```

Per-biome `detail_array.json` lists the detail tiles + per-slot blend
weights (which detail applies to which slot at what strength).

Runtime: MaterialPipeline reads `material_variants.json` (the
sibling manifest, schema in spec 24) + per-biome `detail_array.json`
+ binds them all into the shader's Texture2DArrays.

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
each fragment.

**Audit C2 hardening (2026-05-17)**: per-fragment slot selection is a
**Phase 4 deliverable, not Phase 6** — the renderer cannot claim
spec 23 compliance until the fragment shader actually selects + blends
across active slots per fragment. Pre-audit, Phase 4 shipped with
only the first slot bound; mid + rock textures were dead weight.

Acceptance criteria:
1. Every (biome, slot) declared in `surface_slots.json` has its
   sibling Texture2DArray window (`start, count`) bound on every
   ring material.
2. Fragment shader computes a per-fragment slot weight from
   `slope_deg` (derived from heightmap derivatives at the fragment)
   + `elevation` (vertex Y at fragment) + optional noise (per-biome
   `selector` rule).
3. Final albedo = weighted sum across active slots; weights normalize
   to 1.0 per fragment.
4. Single-slot bundles (legitimate authoring choice for simple
   biomes) collapse to the existing single-slot binding path; the
   selector machinery is opt-in via slot count > 1.

Surface slot world mask (W4 pattern) bakes these into a shared
`Texture2DArrayRD` sampled at world XZ — same approach W4 proved
works. Per-fragment derivation (Phase 4.9.b path) avoids the
authored-mask bake step entirely; either approach satisfies the
acceptance criteria above.

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

**2026-05-18 production default**: the shader's `macro_strength_global`
uniform defaults to `0.0` after Phase 6 visual A/B revealed the prior
0.35 default was contaminating slot detail with macro color (washed
out high-contrast snow_over_rock textures). Macro stays bound and
ready; raise the uniform to >0 when per-biome macros are properly
authored (see "Hidden cross-cutting work" → per-biome macro refactor
in HANDOFF_2026_05_18.md). Macro also fills coverage gaps when no
slot wins a fragment, regardless of `macro_strength_global`.

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
- 2026-05-17 (Phase 5 plan): added on-disk layout for sibling sets
  (`<slot>_variants/v*_*.png`) + per-biome detail overlays
  (`detail/<tag>_*.png` + `detail_array.json`). Both consumed by
  MaterialPipeline at world-load via spec 24 Layer 1+2 contracts.
- 2026-05-17 (Phase 4.9 audit C2): hardened per-fragment slot
  selection as a Phase 4 deliverable (was previously ambiguous —
  the words "Surface slot world mask" left the implementation
  pattern open enough that Phase 4 shipped binding only the first
  slot). Added explicit 4-item acceptance criteria. Phase 4.9.b
  fixes.
