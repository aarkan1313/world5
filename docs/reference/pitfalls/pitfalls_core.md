# W5 Pitfalls — Tier 1 (core)

> Tier 1 = terrain, materials, decoration, foliage, atmosphere,
> lighting, kernels, textures (specs 19-34).
>
> Cap: ≤ 300 lines (split into pitfalls_core_<area>.md when approached).

## #1 — Clipmap ring meshes frustum-culled despite ArrayMesh.custom_aabb

**Symptom**: Walking demo renders flat-brown band (procedural sky's
ground hemisphere color, modulated by tonemap + ambient + sun) where
terrain should be. Material uniforms show `has_siblings=true` +
`sibling_array` bound, but the fragment shader never executes on the
terrain — verified by replacing the fragment body with a forced
unconditional color and seeing no change.

**Cause**: `ClipmapGeometry` builds vertex grids at `y=0` (vertex
shader displaces Y at runtime from heightmap sample). The resulting
`ArrayMesh.custom_aabb` is set to ±500 m Y for culling slack — BUT
in Godot 4.6, `ArrayMesh.custom_aabb` is **not honored by
MeshInstance3D frustum culling**. The renderer reads its culling
AABB from the auto-computed CPU vertex bounds, which have ~zero Y
extent (`y = 0..0.00001` from float epsilon). When the vertex shader
displaces verts to `y = (0 - 0.5) * 2 * 50 = -50` (height_map
samples to 0 on unbound or pre-stream state), every visible vertex
sits 50 m below the AABB → every ring is culled → only the sky
hemisphere renders.

**Fix**: Set `custom_aabb` on the **MeshInstance3D**, not on the
ArrayMesh. Live in `ClipmapRing.configure`:

```gdscript
var local_aabb: AABB = mesh.get_aabb() if mesh != null else AABB()
mesh_instance.custom_aabb = AABB(
    Vector3(local_aabb.position.x, -500.0, local_aabb.position.z),
    Vector3(local_aabb.size.x, 1000.0, local_aabb.size.z))
```

**What didn't work**: Setting `ArrayMesh.custom_aabb` in
`ClipmapGeometry._build_ring_mesh` — silently ignored by 4.6
renderer culling. We leave it set anyway for non-renderer consumers
(raycast, physics, debug overlays) that DO honor it.

**Diagnostic**: Add `mi.visible = false` on every ring. If the
rendered image is identical with rings hidden, the rings weren't
visible to begin with (culled). Then forcing
`ALBEDO = vec3(1, 0, 1)` (fuchsia) in the fragment shader unchanged
proves the fragment never ran.

**Related**: Compounded with pitfall #2 (missing normals) and #3
(back-facing winding) — fixing AABB alone produced black terrain;
all three needed to ship snow.

**First hit**: 2026-05-17, Phase 5.4 first-biome render.

---

## #2 — Clipmap ring meshes built without vertex normals

**Symptom**: After fixing pitfall #1 (AABB), terrain mesh appears
in frustum but renders solid black (or in some lighting setups,
follows ambient color only). The fragment shader runs but lighting
is wrong.

**Cause**: `ClipmapGeometry._build_ring_mesh` populated
`ARRAY_VERTEX` + `ARRAY_TEX_UV` + `ARRAY_INDEX` but not
`ARRAY_NORMAL`. Godot computes a per-fragment normal from
adjacent vertices when normals are absent, but for a flat y=0 mesh
the result is degenerate, and Godot's lighting model treats the
surface as facing away from any light.

**Fix**: Populate `ARRAY_NORMAL` with `Vector3.UP` per vertex (the
vertex shader displaces Y per-vertex but doesn't tangent-space-
recompute — for runtime-displaced flat-grid terrain, up-pointing
normals are the right baseline; future improvement: compute proper
normals in the vertex shader from height_map derivatives).

```gdscript
var normals: PackedVector3Array = PackedVector3Array()
normals.resize(grid_n * grid_n)
for idx in range(normals.size()):
    normals[idx] = Vector3.UP
arrays[Mesh.ARRAY_NORMAL] = normals
```

**Diagnostic**: After fixing AABB, disable backface culling in the
shader (`render_mode unshaded` or `cull_disabled`). If terrain
shows as solid black with disabled culling, normals are the cause.

**Related**: Compounded with pitfall #3 (back-facing winding).

**First hit**: 2026-05-17, Phase 5.4 first-biome render.

---

## #3 — Clipmap ring triangle winding back-facing from above

**Symptom**: After fixing pitfalls #1 and #2 (AABB + normals),
terrain still invisible from a typical above-the-ground camera.
Visible when camera looks UP from below the terrain.

**Cause**: `ClipmapGeometry`'s original index buffer used winding
that was back-facing from Godot's standard above-the-ground camera
viewpoint. With default backface culling enabled, every ring
triangle was rejected before fragment shader ran.

**Fix**: Use front-facing winding `tl, tr, bl` + `tr, br, bl` for
each quad in the grid:

```gdscript
indices[ii] = tl;  ii += 1
indices[ii] = tr;  ii += 1
indices[ii] = bl;  ii += 1
indices[ii] = tr;  ii += 1
indices[ii] = br;  ii += 1
indices[ii] = bl;  ii += 1
```

**Diagnostic**: Add `cull_disabled` to the shader's `render_mode`.
If terrain becomes visible only after disabling culling, winding is
the cause.

**Related**: Pitfalls #1 and #2 — all three needed for snow to render.

**First hit**: 2026-05-17, Phase 5.4 first-biome render.

---

## Regression guards

`engine/tests/visual/test_terrain_capture_baseline_real_device.gd`
ships two new mesh-level tests after this bug class:

- `test_ring_meshinstance_has_nonzero_y_aabb` — catches #1
- `test_ring_mesh_has_upward_normals` — catches #2

Winding (#3) is covered by `engine/tests/unit/test_clipmap_geometry.gd::
test_mesh_has_up_normals_and_front_faces_from_above` which asserts
the first quad's index order.

The TRIO of bugs all silently masked each other — any single fix
alone produced "still no terrain visible" by a different mechanism.
Future renderer changes that touch ring geometry / culling / winding
should ALSO touch these guard tests to confirm new code paths are
covered.

## Doc cap status

~150 lines (well under 300 cap).
