# W5 review handoff — 2026-05-17 (Phase 6 visual A/B post-mortem)

> For: a fresh chat asked to **review the W5 ground texture rendering
> system end-to-end** — world gen, sampler, LOD, rings, biome blend,
> macro, fallbacks — and tell us what's actually wrong. Multi-hour
> session today made many changes; results still don't look right.
> Reviewer should be skeptical of every architectural choice + every
> recent fix. Likely some are wrong.

## What the reviewer needs to do

1. Read this doc.
2. Skim the canonical files (list below).
3. Launch the demo, screenshot a few angles in both alpine + forest, and
   compare to the source textures (also listed below).
4. Report what's structurally wrong vs. just "needs tuning."

Don't trust any of my recent diagnoses without verifying. I've been
chasing in-the-loop and may have multiple bad assumptions stacked.

## Current visible problem (one sentence)

Ground textures render as flat-color washes (alpine = featureless pale
grey, forest = uniform tan-brown) at typical walking-view distances,
despite source textures having strong contrast and character. Looks
like ~200m-distant terrain even when standing on top of it.

## What I tried in this session (in order, all in working tree, uncommitted)

1. **Re-promoted textures** from `D:/tmp/w5_candidates/candidates/` to
   uniform 1024×1024 across both biomes. Originally alpine was 2048,
   forest was 1024 → SiblingTextureArray skipped all forest because
   "first image sets expected_size = 2048." This was real and fixed
   by re-promote.
2. **Macro debug toggle** (keyboard 0-3): mode 0 = production
   (macro at 0.85 weight mixed into olive fallback), 1 = pure slot,
   2 = pure macro at 85% slot mix, 3 = macro off. User confirmed mode
   1 = brightest, modes 0/2 had visible overlay.
3. **Dropped `macro_strength` from 0.85 → 0.35** in shader.
4. **Biome-aware fallback**: added `biome_fallback_colors[8]` uniform.
   `TerrainWorld._compute_biome_ground_avg` loads each biome's
   `ground/albedo.png`, downscales to 1×1, reads pixel, binds as
   per-biome fallback. Replaces the single global olive `vec3(0.35,
   0.45, 0.25)` so coverage gaps (no slot wins) blend to neighbor-
   biome ground color. Confirmed working — green olive patches gone.
5. **Found a coverage gap** at mid-elevation flat ground (slope 15°,
   elev 22m): ground slope band ends at 25°, mid slope band starts
   at 25° with 4° crossfade (so 21-25° is the only overlap), rock
   needs slope ≥ 45°. At flat 22m elev all three slot weights were 0
   → pure fallback color showed through (the "pure white" region in
   one screenshot).
6. **Replaced `w5_variety_sample_3tap`** (stochastic 3-tap blend
   across siblings — what the user identified as causing permanent
   "30% grey mush at ~10m wavelength") with `w5_variety_sample_combined`:
   W4-style region-based variant selection (one sibling per ~512m
   region, hash-of-region-coords) + Heitz-Neyret 2018 within-region
   sampling (triangle grid 3-tap with per-vertex offsets + inverse-
   histogram-transform LUT for contrast preservation).
7. **Built `tx_hn_lut.py`** pipeline tool that generates per-channel
   inverse-CDF 256×1 LUT (`albedo_tinv.png`) next to each albedo. 23
   LUTs generated for walking_demo.
8. **`SiblingTextureArray.build` called twice** — once for albedo,
   once for albedo_tinv — parallel Texture2DArrays bound layer-matched.
9. **`MaterialPipeline.bind_variety_combined`** binds the new uniforms:
   `region_size_m`, `edge_blend_m`, `world_seed`, `sibling_t_inv_array`,
   `has_t_inv`.
10. **HN had visible white-patch bug** (variance correction was a no-op
    in my impl — math was `mean + (blended - mean) = blended`, didn't
    actually do anything; T_inv LUT remap on top produced unexpected
    output in some regions). Added `hn_enabled` uniform + keyboard
    toggle 4=off / 5=on. **Defaulted hn_enabled=false** for the session.
11. **Widened slot bands** (3°→10°) to close coverage gaps. THIS WAS
    WRONG: wide bands caused ground+mid+rock to all overlap with
    nontrivial weights, slot loop normalizes by sum so every fragment
    became `(ground + mid + rock) / 3` everywhere = mush.
12. **Narrowed bands back to 3/4/5°** AND widened slot ranges
    (`ground.elev_m: [-50, 15]` → `[-50, 50]`, same for slope). Idea:
    wide range = ground always wins somewhere; narrow band = clean
    handoff to neighbor slot only in narrow strips at the boundary.
    Coverage gap closed without everywhere-mixing.
13. **`sibling_tile_m` default 4 → 16**. With `region_size_m=512`, a
    4m tile repeats 128× per region (visible wallpaper); 16m repeats
    32× per region (allegedly more natural at eye height).
14. **MIPMAP FIX (most recent)**: discovered `SiblingTextureArray`
    builds Texture2DArray via `create_from_images` without calling
    `generate_mipmaps()` on each image first. Shader sampler was also
    `filter_linear` (no mipmaps). At distance, GPU sparse-sampled raw
    1024² pixels → averaged to texture mean color = "flat washed out."
    Fix: call `img.generate_mipmaps()` before append, change sampler
    to `filter_linear_mipmap_anisotropic`.
    **User reports: "doesn't really look different."**

That last bullet is the key data point — the mipmap fix should have
been dramatic. It wasn't. Either I'm wrong about mipmaps being the
cause, or the fix didn't apply correctly (cached shader? cached
texture?), or there's something more fundamental wrong upstream.

## Suspect list for the reviewer

In rough priority order:

1. **The combined sampler I wrote may be fundamentally wrong.**
   Specifically `w5_variety_sample_combined` + `w5_hn_sample` in
   `engine/shaders/variety_common.gdshaderinc:215-410`. Reviewer
   should trace what it actually outputs given the textures + uniforms.
   The HN impl I wrote was admittedly hand-wavy (variance correction
   no-op, LUT remap may interact badly).
2. **`hn_enabled` is false but the macro overlay is still strong**.
   Even at mode 0 with mipmaps fixed, output is washed out. Means
   macro at 0.35 may still be killing things, OR `frag_fallback` is
   the average ground color and we're seeing 30% of (avg-color +
   macro-color) = washed grey on top of slot detail.
3. **Mipmap fix didn't actually land**. Godot may be caching the old
   shader binary or texture array. Reviewer should verify by adding
   a debug shader-param toggle that returns `vec4(1, 0, 1, 1)` from
   the new sampler entry point — if magenta appears, new shader is
   live; if not, hot-reload is broken.
4. **Slot weight normalization** may still be mushing things at slot
   boundaries (3-4° bands aren't actually narrow enough at typical
   slopes — they ARE 100% of the time at 25° slope between ground
   and mid). Reviewer should consider winner-take-all per fragment.
5. **Biome-weighted fallback** is `frag_fallback = biome_w * biome_avg_color`.
   When the player is anywhere in a biome's auto_rule range, this
   evaluates to a non-zero color even when a slot fully wins. Then
   shader does `base = mix(frag_fallback, macro_col, 0.35)` → base
   already has biome-avg-color mixed in. Then slot is mixed on top at
   0.7. Slot is dominant (70%) but 30% is contaminated. With low-
   contrast snow source, that 30% washout matters more than for high-
   contrast source. **This is probably real.**
6. **Spec 21 vs spec 23** alignment. Spec 23 says "Layer 1 sibling
   selection is per-region with edge blend." Spec 24 says variety
   layers are 1/2/3. Reviewer should check if my new sampler agrees
   with what the spec actually defined, or if I freelanced a hybrid.
7. **Source textures themselves may be flat at high mip levels**.
   Mean of snow_over_rock = (178, 180, 179) — pale grey. Mean of
   leaf_litter = ~tan. At mip 6+ that average IS what shows. Real
   AAA terrain uses world-anchored UVs + triplanar to break the
   "mip averages flat" problem.

## Canonical files to read

| File | Lines | What it does |
|---|---|---|
| `engine/shaders/terrain_clipmap.gdshader` | ~520 | Main terrain shader. Fragment is the contested zone. |
| `engine/shaders/variety_common.gdshaderinc` | ~410 | All sampling/variety helpers. NEW: `w5_avalanche_u32`, `w5_region_*`, `w5_hn_sample`, `w5_variety_sample_combined` at bottom. Old `w5_variety_sample_3tap` kept for back-compat. |
| `engine/scripts/terrain/TerrainWorld.gd` | ~890 | Top-level orchestrator. `_load_world_bundle` is bundle wiring; `_bind_slots_with_catalog` is the main binder; `_compute_biome_ground_avg` is new fallback computation; `_unhandled_input` has the diagnostic key toggles. |
| `engine/scripts/terrain/material/MaterialPipeline.gd` | ~400 | All shader uniform binders. New: `bind_biome_fallback_colors`, `bind_variety_combined`. |
| `engine/scripts/terrain/material/SiblingTextureArray.gd` | ~125 | Builds the Texture2DArray. JUST FIXED to generate mipmaps. |
| `engine/worlds/walking_demo/biome_catalog.json` | 162 | Two biomes (alpine + forest), per-biome surface_slots + auto_biome_rules. Recently edited: widened slot ranges, kept narrow band widths. |
| `engine/worlds/walking_demo/material_variants.json` | ~90 | The manifest. `region_size_m: 512`, `edge_blend_m: 48`, `world_seed: 42`. 6 slots (2 biomes × 3 slots each). |
| `pipeline/world5/textures/tx_hn_lut.py` | ~110 | NEW pipeline tool. Generates albedo_tinv.png next to every albedo. |
| `docs/HANDOFF_2026_05_17.md` | ~280 | Earlier session handoff (before today's debugging). Read for context on Phase 6 unblock + audit. |

## Reference docs (read these for system context)

- `docs/specs/21_TERRAIN_RENDERER.md` — clipmap + per-fragment slot selection
- `docs/specs/22_BIOME_CATALOG.md` — auto_biome_rules + per-biome surface_slots
- `docs/specs/23_MATERIALS_PBR.md` — slot model
- `docs/specs/24_GROUND_VARIETY.md` — Layer 1/2/3 + region selection contract
- `docs/specs/13_QUALITY_TIERS.md` — per-tier knobs
- `docs/reference/PITFALLS.md` — W4 pitfalls inherited

## Source textures (the ground truth)

Walking demo's current picks (re-promoted today):

| Biome | Slot | Base | Siblings |
|---|---|---|---|
| alpine | ground | `snow_over_rock_base` (high-contrast B&W rock-through-snow) | `_s43`, `_s45` |
| alpine | mid | `lichen_moss_base` | `_s43`, `_s44`, `_s45` |
| alpine | rock | `dark_slate_base` (BFL) | `local_dark_slate`, `local_weathered_basalt`, `local_schist_layered` |
| forest | ground | `leaf_litter_base` (visible leaves, brown variation) | `_s44`, `_s242`, `_s342` |
| forest | mid | `ferns_base` | `_s43`, `_s44`, `_s45` |
| forest | rock | `granite_mossy_base` | `_s43`, `_s44`, `_s45` |

Source candidates at `D:/tmp/w5_candidates/candidates/<biome>/<slot>/<tag>/{albedo,normal,roughness,ao,height}.png`.
Contact sheets: `D:/tmp/w5_candidates/tile_tests/tile_test_<biome>_<slot>.png` —
**read these to see what the textures actually look like**.

## Quality tier configuration

Demo uses `high` tier (verified, hard-coded? — reviewer please check
`_apply_quality_tier_defaults`):

```
high:
  terrain_rings: 5
  terrain_grid_n: 256
  terrain_step0_m: 0.5
  terrain_stepN_m: 8.0
  terrain_pbr_tile_size_m: 8.0    <-- BUT shader default is 16, set by sibling_tile_m uniform default
  terrain_macro_tile_size_m: 256.0
  terrain_sibling_blend_freq: 0.3 <-- bound via bind_sibling_blend_freq; ONLY used by legacy 3tap sampler; NEW combined sampler ignores it
```

**Likely real bug**: `terrain_pbr_tile_size_m: 8.0` from quality tier
is bound via... actually I don't see any binder that pushes this
into the shader's `sibling_tile_m` uniform. So the tier value is
documented but unused; shader uses its own default of 16. Reviewer
should grep `terrain_pbr_tile_size_m` to confirm.

## The rendering pipeline (the loop, fast version)

For a fresh chat, here's the path from "TerrainWorld._ready" to "pixel on screen":

1. **Build clipmap rings**: `_geometry.build(ring_count, ring_vertex_grid, inner_cell_size_m)` → 5 nested mesh rings (high tier defaults).
2. **Per ring**: create `ShaderMaterial` (terrain_clipmap.gdshader), assign as `material_override` on its MeshInstance3D.
3. **Load bundle**: read `material_variants.json` + `biome_catalog.json`. Build `sta` (albedo Texture2DArray) + `sta_tinv` (LUT array). Compute per-biome ground avg colors.
4. **Bind**: `_bind_slots_with_catalog` walks slots, builds per-slot windows/elev_bands/slope_bands/biome_indices, passes to `MaterialPipeline.bind_all_slots`. Then `bind_biome_auto_rules`, `bind_biome_fallback_colors`, `bind_variety_combined`.
5. **Heightmap pages**: streamed async via `AssetStream` → `ResidencyManager` → `RingHeightArray.update_page`. Camera move triggers `_required_pages_signature` dirty-check → rebase rings as needed.
6. **Per-frame fragment shader**:
   - Compute biome_weight[b] via softmax over auto_biome_rules.
   - Compute frag_fallback = sum(biome_w[b] * biome_fallback_colors[b]).
   - Sample macro_albedo (world-spanning anti-repeat layer). macro_strength = 0.35 (currently).
   - base = mix(frag_fallback, macro_col, macro_strength).
   - For each slot i: slot_weight = w5_slot_weight(elev_band[i], slope_band[i], y, slope_deg) * biome_w[slot_biome_index[i]].
   - For each winning slot: sib = w5_variety_sample_combined(...) — picks variant by region hash, samples it, crossfades at borders.
   - weighted += sib * slot_weight; wsum += slot_weight.
   - If wsum > 0: base = mix(base, weighted/wsum, 0.7). Else: base = base (fallback only).
   - (Layer 2 detail overlay is bound but no detail tiles authored.)
   - (Terrain haze applied at edge of clipmap.)

## Verify commands

```bash
python -m world5.verify --fastest    # pytest (~5s)
python -m world5.verify              # + gut + preflight (~8s)
python -m world5.world_contract --world engine/worlds/walking_demo
```

Currently green: 174 pytest, gut OK, preflight 0 errors / 1 warning
(STATE.md over cap, unrelated).

## Demo launch (manual)

```
C:/Godot/v4.6.2/Godot_v4.6.2-stable_mono_win64/Godot_v4.6.2-stable_mono_win64.exe \
  --path demo demo/scenes/walking_demo.tscn
```

Keyboard during demo:
- WASD = walk, mouse = look, Shift = sprint, ESC/Tab = release mouse
- 0/1/2/3 = macro_debug_mode (0=prod, 1=pure slot, 2=pure macro w/ slot, 3=macro off)
- 4 = HN sampler off (default), 5 = HN sampler on (has known white-patch bug)

## What's actually committed vs. uncommitted

Uncommitted (this session): everything above. See `git status --short`.
Working tree dirty. Reviewer can either:
- Stash + checkout main (HEAD: `a5b0dca`) to see the pre-debug state
- Or work with current dirty tree (recommended — that's what's failing visually)

## Honest opinion

I think there are 3 stacked bugs:

(a) **Macro+fallback contamination** still washing things even at 0.35.
    The biome-aware fallback was a good fix for green-olive, but it
    means the "neutral" base now matches the biome's avg color, which
    for low-contrast siblings IS the washed-out look.

(b) **Tile size mismatch** between quality tier (8m) and shader
    default (16m) — nobody binds the tier value. Either 8m looks
    better in-engine or 16m does, but we never tested 8m because
    the binder doesn't exist.

(c) **Possibly mipmap fix didn't actually land** in the running build.
    Need verification.

A clean-slate reviewer should probably:
1. Strip macro entirely as a test (set `has_macro = false`)
2. Strip biome_fallback (revert to single olive)
3. Confirm with magenta debug that mipmap fix is live
4. THEN add macro + fallback back, one at a time, with clear A/B

That's what I should have done 2 hours ago.

## Doc cap status

~250 lines (under 350 cap).
