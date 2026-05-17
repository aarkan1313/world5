# Phase 4.10 — Clipmap Correctness (W4 PITFALLS lifted)

> Phase: 4.10 (re-opening Phase 4 again per user-observed bugs)
> Status: 🚧 opening 2026-05-17
> Triggered by: User walking-demo screenshots 2026-05-17 showing
> (1) elevation cliff at ring boundary + (2) visible square tile
> pattern + (3) "i can also clearly see the rings as i move"
> Driven by: `D:/assets/world 4/docs/reference/PITFALLS.md`
> recurrences #11 + #14 + #15 + #30/#32

## Why this exists

After Phase 4.9.c + 5.4.b shipped, the walking demo still showed
three user-visible artifacts. Diagnosis (informed by W4 PITFALLS
doc per user redirect) matched each artifact to a documented W4
failure mode with a documented fix:

| User-visible | W4 PITFALL | Status in W5 |
|---|---|---|
| Cliff at ring boundary (image 1) | **#11 morph zones missing/wrong** | Partial: `morph_factor` uniform exists but uses camera-distance to ring CENTER (not per-vertex distance to ring EDGE). h_parent samples same ring at 2× cell (not actual coarser ring). |
| Rings visible while walking | **#14 full-ring regen on snap** | Present: `_update_ring_height_array` lines 500-505 discards entire RingHeightArray when min_xz drifts. Pages re-stream from scratch every snap. |
| Tile square pattern (image 2) | **#30/#32 slot selection uses per-ring slope** | Present: Phase 4.9.b derives slope in vertex shader via 4-tap on own-ring heightmap. Different rings = different slope at same world XZ = different slot mix = ring grid visible. |

**The fix is not to re-invent — it's to lift W4's documented
solutions.** Each sub-task cites the W4 PITFALL it implements.

## Sub-tasks

### 4.10.a — Morph zones done right (PITFALLS #11)

**Problem (re-stated)**: visible elevation cliff at ring boundary.
Per-ring heightmaps encode different values for the same world XZ
(inner = fine, outer = blurred). Pixels at the boundary land on
different rings → step.

**Current state**: `morph_factor` is a single per-ring uniform driven
by camera distance to ring center. Wrong distance metric — morph
should be driven by **per-vertex distance to ring's outer edge**.
Also h_parent samples same ring's pages at 2× cell rather than the
ACTUAL coarser ring's heightmap.

**Acceptance**:
- Per-vertex morph factor computed in vertex shader from
  `(vertex_world_xz, ring_center, ring_half_extent, morph_band_frac)`
  — ramps 0 inside ring → 1 at outer edge
- h_parent samples the next-coarser ring's heightmap (binds outer
  ring's Texture2DArray to the inner ring's material as an extra
  uniform, OR samples the next-coarser MIP of the inner ring's
  height_array as approximation)
- At ring boundary, h converges to outer ring's value → no cliff
- Per-fragment normal morphs identically (lighting matches geometry)
- Regression test: capture from camera at fixed offset; assert no
  height delta > 0.1m within morph band at ring boundary

**Approach**:
- Replace per-ring uniform `morph_factor` with per-ring uniforms
  `ring_center_xz: vec2`, `ring_half_extent_m: float`,
  `morph_band_frac: float`
- Vertex shader computes `m = compute_morph(vertex_world_xz, ...)`
- Bind parent ring's `height_array` as `parent_height_array` sampler
  on each inner ring's material; parent ring's min_xz +
  page_extent + pages_per_side as their own uniforms
- For the outermost ring, h_parent falls back to its own value
  (`m = 0` always at outer ring)

**Effort**: 2 sessions

### 4.10.b — Incremental RingHeightArray on snap (PITFALLS #14)

**Problem**: every clipmap snap drops the entire RingHeightArray +
re-streams pages from scratch. Pages that are still in the new
window get re-fetched anyway. Symptoms: visible "ring chasing" /
"placeholder ground" while walking.

**Acceptance**:
- On snap, RingHeightArray re-maps existing pages to new local
  coords (most are still in the window, just shifted)
- Pages outside the new window evicted (existing path)
- Pages newly inside the window streamed (existing path)
- No full-ring rebuild from scratch in the snap-only case
- Regression test: walk across N page boundaries; assert page
  load-count == newly-required-pages (not full-ring)

**Approach**:
- In `_update_ring_height_array`, instead of `rha = RingHeightArray.new()`
  when `aligned_min != rha.min_xz`, call new
  `rha.rebase(new_min_xz)` method that recomputes local coords
  for existing entries
- `RingHeightArray.rebase()`: for each (key, image), compute the new
  local coord under new_min_xz; if still in [0, pages_per_side),
  keep at new key; otherwise drop. Update self.min_xz.
- Add TDD test: `rebase()` keeps in-window pages, drops out-of-window

**Effort**: 1 session

### 4.10.c — World-stable slope for slot selection (PITFALLS #30/#32)

**Problem**: per-fragment slot selection uses vertex-shader-derived
slope from own-ring heightmap. Adjacent rings disagree on slope at
the same world XZ → slot decision flips at ring boundary → visible
square pattern matching ring grid (NOT sibling tile grid).

**Acceptance**:
- Slope used for slot selection comes from a world-stable source
  (NOT the active ring's height texture)
- Adjacent rings at the same world XZ make the same slot decision
- Visible: no ring-aligned square pattern when slot selection active
- Per-fragment slope sample footprint is per-tier knob
  (`terrain_surface_slot_slope_sample_m`, e.g. 32m / 64m / 128m
  per W4 default)

**Approach** (two paths, pick lower-cost):

*Path A — sample slope from outermost ring only*: every ring's
fragment shader samples slope from the outermost ring's heightmap
(bind as `world_slope_height` sampler). Outermost ring has the
coarsest grid but covers the widest extent → stable across all
rings.

*Path B — slope kernel pre-bake*: at world bake, kernel emits a
slope field alongside the heightmap. Sample slope from the slope
field, not derived from height in shader. (Heavier; requires
spec 19 kernel extension. Phase 5.7 sprint material.)

For Phase 4.10, **Path A** — cheapest path that fixes the visible
bug. Path B is the long-term right answer when kernel system
matures.

**Effort**: 1-2 sessions

## Sub-task dependencies

```
4.10.a (morph zones) ── independent
4.10.b (incremental snap) ── independent
4.10.c (stable slope) ── independent
```

All three are independent; can be tackled in any order. Recommend
.a first (most visible bug) → .c (second most visible bug) → .b
(most subtle, perf optimization framing).

## Close criteria

- All 3 sub-tasks shipped with acceptance criteria met
- 5/5 verify layers green
- Build note `phase_4_10_close_2026_05_XX.md`
- ROADMAP + STATE updated; pitfalls_core.md extended with W5-side
  recurrences citing W4 source PITFALLs
- User walks the demo + confirms no cliff + no ring-grid pattern +
  no "ring chasing"
- Phase 4 is *really* done this time (4.9 + 4.10 closed all
  audit-driven gaps)

## What this is NOT

- NOT a rewrite of the clipmap renderer. Targeted fixes lifting
  documented W4 solutions.
- NOT extending to Phase 5/6 features. Strict Phase 4 hardening.
- NOT changing the spec contracts; specs 21/23/24 stay as-is,
  shader implementation catches up.

## Risk register

- **Morph zones touch every ring material binding**: 4.10.a requires
  binding parent ring's height_array as a uniform on every inner
  ring's material. Mid-rebuild state may bind parent before child
  loads → guard with `has_parent_height_array` flag.
- **Path A (slope from outer ring) loses fine slope detail at eye
  height**: trade-off documented in W4 PITFALLS #30 — slot selection
  doesn't need eye-resolution slope, it needs broad slope categories
  (ground/mid/rock). Coarser sample is fine for material selection
  but bad for any per-fragment shading effect. We only use it for
  slot weights; shading still uses fine normal.
- **Incremental snap (4.10.b) has indexing edge cases**: page coord
  transformation across snap is tricky when the snap distance is
  larger than the page extent. Cover via TDD tests with multiple
  snap distances.

## Doc cap status

~170 lines (under 350 cap).
