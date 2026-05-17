# Phase 5.4 — First biome (alpine) shipped + brown-band bug class fixed

> Date: 2026-05-17
> Closes: Phase 5.4 (alpine biome promote → render → visual verify)
> Opens: nothing new — Phase 5.6 calibration when ready; Phase 6
>        (second biome / forest) is just another promote run

## What landed

**Textures** (author-supplied, gitignored): texture team delivered
91 candidates across 16 (biome, slot) pairs at `D:/tmp/w5_candidates/`:
- 63 BFL flux-2-pro outputs (2048², albedo from flux-2-pro,
  derived PBR via `derive_pbr_v2.py`)
- 28 local NVFP4 winners (1024², full PBR from W4 hybrid pipeline)
- Per-slot inventory: alpine (ground 4-7 / mid 4 / rock 4-5) +
  forest (ground 4-6 / mid 4-6 / rock 4-4)

**Walking demo alpine biome promoted**:
```bash
python -m world5.textures.promote \
  --world engine/worlds/walking_demo \
  --candidates-root D:/tmp/w5_candidates/candidates \
  --biome alpine \
  --slot ground --base firn_dense_base \
                --siblings firn_dense_s43 firn_dense_s44 firn_dense_s45 \
  --slot mid    --base lichen_moss_base \
                --siblings lichen_moss_s43 lichen_moss_s44 lichen_moss_s45 \
  --slot rock   --base granite_lichen_base \
                --siblings granite_lichen_s43 granite_lichen_s44 granite_lichen_s45
```

48 files copied → `engine/worlds/walking_demo/materials/biome_alpine/`,
9 sibling entries in `material_variants.json`. Preflight
(`world_contract --world ...`) clean: 0 errors / 0 warnings.

## Brown-band bug class (three compounding bugs)

After promote, capture still showed flat brown band. Two outside
audits + diagnostic spelunking found THREE bugs all masking each
other:

### Bug 1: `ArrayMesh.custom_aabb` silently ignored

`ClipmapGeometry._build_ring_mesh` set `mesh.custom_aabb` to ±500 m
Y to give vertex shader heightmap displacement enough culling slack.
**Godot 4.6's MeshInstance3D ignores ArrayMesh.custom_aabb**; it
auto-computes from CPU vertex data which has zero Y extent
(verts are flat y=0; the shader displaces at runtime). Rings
frustum-culled the moment vertex shader pushed any visible vertex
off the y=0 plane.

Fix: Set `custom_aabb` on the **MeshInstance3D**, not the mesh.
Live in `ClipmapRing.configure`. Pitfall #core-1.

### Bug 2: Missing vertex normals

`ClipmapGeometry` populated `ARRAY_VERTEX` + `ARRAY_TEX_UV` +
`ARRAY_INDEX` but NOT `ARRAY_NORMAL`. Without normals, Godot's
lighting model treats the surface as facing away from any light →
black terrain even when visible.

Fix: Add `ARRAY_NORMAL` filled with `Vector3.UP`. Pitfall #core-2.

### Bug 3: Back-facing triangle winding from above

Original index buffer used a winding that was back-facing from the
typical above-the-ground camera viewpoint. With default backface
culling, every ring triangle was rejected before fragment ran.

Fix: Change winding to `tl, tr, bl` + `tr, br, bl`. Pitfall #core-3.

### Bonus: `cast_shadow=OFF` on ring meshes

The displaced ring meshes were casting self-shadows onto themselves,
producing dark blotchy artifacts. Set `cast_shadow =
SHADOW_CASTING_SETTING_OFF` per ring (tests guard via
`test_ring_mesh_does_not_cast_self_shadows`).

## Why this took two audits + a diff to spot

Each bug alone produced "still no terrain visible" by a DIFFERENT
mechanism:
- AABB only: forced cyan fragment ALBEDO showed sky color (rings
  culled, fragment never ran)
- AABB + normals fix only: forced fragment ran, but rings were
  rejected by backface culling (winding)
- AABB + winding only: visible rings, but solid black (no normals)
- All three: snow

The **shader-state integration tests** (`test_terrain_world_material_binding`)
passed throughout because they only check `mat.get_shader_parameter(...)`,
not whether pixels actually rasterize. New regression guards added
to `test_terrain_capture_baseline_real_device.gd` to catch the bug
class at the mesh level without needing SubViewport pixel capture:
- `test_ring_meshinstance_has_nonzero_y_aabb` (catches #1)
- `test_ring_mesh_has_upward_normals` (catches #2)
- `test_clipmap_geometry::test_mesh_has_up_normals_and_front_faces_from_above` (catches #3)

## Texture storage policy (decided 2026-05-17)

Promoted PBR textures total 297 MB for alpine alone (BFL outputs at
2048² + 4-12 MB per map). **Not committed to git.** Per .gitignore:
- `engine/worlds/**/materials/**/*.png` — author-supplied
  per-machine; regenerable from the candidates pipeline
- `engine/worlds/**/materials/**/*.png.import` — Godot import
  sidecars
- Same for `.webp` and `.jpg`

What IS tracked: `material_variants.json` + `surface_slots.json` +
`detail_array.json` + `.gitkeep`'d scaffold dirs (document the
expected world bundle structure). Manifests are tiny + diff-friendly;
textures are 8-figure-character binary that bloats forever.

Implication for fresh-machine setup: a new dev needs to either
(a) run the texture pipeline themselves to produce candidates +
promote, or (b) receive a pre-promoted bundle out-of-band. CI uses
the synthetic test fixtures we already have (`SiblingTextureArray`
unit tests build PNGs in `user://` on the fly).

## Verify status

5/5 layers green stable in 47s:
- pytest 139 passed
- gut headless all passed
- gut_real_gpu all passed
- preflight 0 errors / 0 warnings (repo mode; with `--world` flag
  walking demo passes 0 errors / 0 warnings)
- capture all passed (including the 2 new mesh-level regression guards)

## Visual confirmation

`user://_capture_walking_demo.png` (1152×648) shows displaced
firn-snow alpine terrain. No brown band. Sun-lit, snow-textured,
heightmap-displaced. End-to-end pipeline live.

## What's load-bearing post-5.4

- `MeshInstance3D.custom_aabb` set in `ClipmapRing.configure` is the
  ONLY thing keeping rings in frustum after vertex displacement.
  Any new renderer pattern (instanced rings, generated rings, etc.)
  must set this or rings will silently cull.
- `Vector3.UP` normals + `tl,tr,bl` + `tr,br,bl` winding in
  `ClipmapGeometry._build_ring_mesh` are coupled — changing one
  without the other reintroduces the bug.
- Texture storage policy: do NOT commit textures into git. promote.py
  + .gitignore enforce this together.
- The brown-band bug class taught us: shader-state assertions are
  necessary but NOT sufficient. The new mesh-level regression
  guards close the gap; if you add a new ring-mesh code path,
  extend those guards.

## Doc cap status

~155 lines (well under 350 build-note cap).
