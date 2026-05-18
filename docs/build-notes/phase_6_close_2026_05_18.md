# Phase 6 close — 2026-05-18

> Phase: 6 (forest = second biome rendering end-to-end)
> Status: ✅ closed
> Driver: Phase 6 unblock (`8a087c8`) wired the GDScript biome_weights
> mirror; this session resolved the visual-A/B issues that surfaced
> when the user first launched the multi-biome demo.

## Summary

Phase 6 shipped biome catalog + per-fragment biome_weights via softmax
over auto_biome_rules. User launch revealed the demo still didn't read
as "alpine vs forest" because of a cascade of latent rendering bugs
inherited from earlier phases that were only visible once forest layers
actually entered the sibling array. Resolved across this session.

## What landed

### Texture pipeline + content
- **Promoted 91-candidate batch** (`D:/tmp/w5_candidates/candidates/`)
  to uniform 1024×1024 across both biomes. Fixed silent
  size-mismatch skip (alpine was 2048, forest was 1024 → forest got
  fully dropped from SiblingTextureArray).
- **Final picks**: full 8-variant pool per slot drawn from BFL + LOCAL
  candidate families:
  - alpine ground: snow_over_rock × 3 + firn_dense / windpack +
    local_fresh_powder / local_windpack / local_firn_dense
  - alpine mid: lichen_moss × 4 + scree / wet_rock_moss +
    local_lichen_thin_snow / local_moss_grey_rock
  - alpine rock: dark_slate (BFL) + 5 local slates + granite_lichen
  - forest ground: leaf_litter × 4 + dirt_mossy / pine_needles +
    local_dark_humus / local_pine_needles_brown
  - forest mid: ferns × 4 + roots_moss / mossy_log +
    local_lichen_on_rock_brown / local_dark_moss_dense
  - forest rock: granite_mossy × 4 + bedrock_lichen + local granites
- **48 albedo layers + 48 T_inv LUTs** total. SiblingTextureArray
  builds parallel albedo / normal / roughness / AO / T_inv arrays.

### Sampling pipeline (the big architectural change)
- **Replaced broken stochastic 3-tap** sampler (`w5_variety_sample_3tap`,
  kept for back-compat) which smeared 3 random siblings per fragment.
- **W3 M11-derived sampling stack**:
  - `w5_hex_sample_albedo` — proper Heitz-Neyret 2018 hex sampling
    with per-vertex hash-jitter + hash-rotation + variance-preserving
    blend (`mean + (w0*d0+w1*d1+w2*d2)/sqrt(w0²+w1²+w2²)`). Replaced
    my prior broken HN impl that had a no-op variance correction.
  - `w5_variety_sample_plane` — region-based variant selection within
    one projection plane (region hash picks ONE variant per ~512m
    region, 4-corner bilinear crossfade within `edge_blend_m` of borders).
  - `w5_variety_sample_triplanar` — top-level entry: samples sibling
    array from XY/XZ/YZ planes, blends by world normal. Steep slopes
    no longer stretch the planar UV.
- **`v_world_normal` varying** added — computed from heightmap finite
  differences (same source as `v_slope_deg`), feeds triplanar.

### PBR pipeline (parallel chat's fix)
- **Normal/roughness/AO sibling arrays loaded** via SiblingTextureArray
  alongside albedo, layer-matched. Shader consumes all four for proper
  PBR lighting via NORMAL_MAP / ROUGHNESS / AO outputs.
- **Mesh tangents added** to ClipmapGeometry so normal maps can
  actually affect lighting.

### Slot/biome accumulator math (last bug found)
- **Replaced wrong `mix()` chain** that the prior PBR-wiring chat had
  used: `biome_slot_rgb[bi] = mix(prev, sib, alpha)` is NOT a
  weighted average — it's a successive overwrite biased toward whichever
  slot ran last in the loop. Result: visible meshing of all slot
  textures together.
- **Proper W3-pattern accumulator**: `acc += sib * weight; cov += weight`
  per loop iteration, then `acc / cov` after the loop. Two-stage:
  per-biome normalize first, then cross-biome blend by `biome_w`.
- **Zero-init accumulators** so neutral defaults (e.g. `vec3(0.5, 0.5, 1)`
  for normal) don't bias the weighted mean.

### Mipmap fix
- **`Image.generate_mipmaps()`** added to SiblingTextureArray.build
  before `create_from_images`. Without mipmaps, GPU sparse-samples
  raw 1024² pixels at distance, averaging to texture mean color =
  flat washed-out look.
- **Shader sampler hint** changed from `filter_linear` to
  `filter_linear_mipmap_anisotropic` for proper trilinear + aniso
  filtering on foreshortened terrain.

### Per-biome fallback color
- New `biome_fallback_colors[8]` uniform. `TerrainWorld._compute_biome_ground_avg`
  loads each biome's `ground/albedo.png`, downscales to 1×1, reads the
  average pixel color. Bound layer-matched.
- Fragment shader computes `frag_fallback = sum(biome_w[b] * biome_fallback_colors[b])`.
  Replaces single hardcoded olive `vec3(0.35, 0.45, 0.25)` that was
  producing visible green-olive patches in coverage gaps.

### Catalog tuning
- Widened slot elev/slope **ranges** to cover the full demo terrain
  (ground covers `[-50, 50]` elev / `[0, 50]` slope) so no coverage
  gaps. **Narrowed band widths** back to 3°/4°/5° so slot crossfades
  only happen in narrow strips at the band edges (not everywhere).

### Cleanup (after audit)
- **Stripped `macro_debug_mode` uniform + keyboard handler**. Production
  default was contaminating slots with 35% macro blend. Now a single
  `macro_strength_global` uniform defaults to 0 — slots are fully
  authoritative when they win. Macro stays bound for future per-biome
  authoring + the gap-fill case.
- **Stripped `hn_enabled` uniform** + keyboard handler. Was orphaned
  after W3 hex sampling replaced the broken HN.
- **Added debug log** at "binding slots on rings" showing
  `region_size_m / edge_blend_m / world_seed` actually-bound values
  so future regressions are diagnosable from one log line.

## Tools added

- **`pipeline/world5/textures/tx_hn_lut.py`** — per-channel inverse-CDF
  256×1 LUT generator. Writes `albedo_tinv.png` next to every
  `albedo.png`. CLI: `python -m world5.textures.tx_hn_lut --world
  engine/worlds/walking_demo`.

## Demo state

Launch log (confirms full pipeline):
```
[INFO ] [terrain_world] sibling array built  slots=6 layers=48
        tinv_layers=48 normal_layers=48 roughness_layers=48 ao_layers=48
[INFO ] [terrain_world] binding slots on rings  slot_count=6 biome_count=2
        biome_weights_active=true has_catalog=true rings=5
        region_size_m=512.0 edge_blend_m=48.0 world_seed=42
```

## Verify

```
python -m world5.verify --fastest    # pytest 174 passed
python -m world5.verify              # + gut + preflight, all green
```

## Known follow-ups (not blocking close)

1. **Source texture polish**: even with the sampling pipeline correct,
   diffusion-generated PBR is hit-or-miss vs. photogrammetry. Quality
   is bound by what the texture team's pool delivers, not the renderer.
2. **Phase 5.4.b.3 detail overlays** still deferred. W3 had a close-
   range detail layer (`grass_detail_*`, etc.) that adds high-frequency
   surface character — significant lift if/when we author detail tiles.
3. **Per-biome macro authoring**: macro_albedo.json is world-scoped
   today. When a 3rd biome lands we'll want per-biome macros (cheap
   refactor — wire as Texture2DArray indexed by biome).
4. **Triplanar region-pick uses world XZ for all 3 planes**: reduces
   variety on cliffsides (X and Z projections pick the same variant).
   Acceptable for v1; revisit if cliffs read poorly.

## Doc cap status

~135 lines (under 200 cap).
