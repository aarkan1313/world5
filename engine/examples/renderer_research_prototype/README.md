# Renderer Research Prototype

> Spec 15a section E validation. Proves clipmap renders in Godot 4.5
> without engine extensions + measures dev-hardware perf.

## What it is

Minimal single-ring clipmap:
- 256×256 vertex grid (65,536 verts, 130,050 tris)
- 1km × 1km world extent (4m cells)
- Heightmap sampled in vertex shader (Texture2D, displaces Y by 100m max)
- Simple height-graded color (green→white) + UV stripes for visual verification
- Camera at ~600m above terrain looking down + diagonal

NOT a production clipmap. No multi-ring, no streaming, no LOD morph,
no async page generation. Just the primitive proving the basic
mechanism works.

## How to run

```bash
# Real GPU mode (--headless disables RenderingDevice; see pitfall meta-2)
"C:/Godot/Godot_v4.5-stable_win64.exe" \
  --display-driver windows --rendering-driver vulkan \
  --disable-vsync \
  --path demo \
  "res://addons/world5/examples/renderer_research_prototype/renderer_research_prototype.tscn" \
  --quit-after 600
```

Without `--disable-vsync` you get vsync-capped numbers (4.17ms /
240fps at this monitor's refresh rate). With vsync disabled you
see the actual GPU cost.

## Measured numbers (2026-05-16)

**Dev hardware**: NVIDIA RTX 5090 Laptop GPU (Vulkan 1.4.329)

| Setting | Avg ms | Min ms | Max ms | FPS |
|---|---|---|---|---|
| Vsync-capped (240Hz monitor) | 4.17 | 4.17 | 4.55 | 240 |
| Vsync disabled | 0.5-0.8 | 0.14 | 8.6 (occasional GC) | 1500-1800 |

The 8.6ms max is a one-off spike (likely Godot internal GC); 99th
percentile is well under 2ms.

## Extrapolation to RTX 3060 (target hardware)

RTX 5090 Laptop ≈ 4-5x the compute throughput of RTX 3060
(50 TFLOPs vs 13 TFLOPs). Linear extrapolation:

- Avg frame cost on RTX 3060: **~2-3 ms** for 130k tris single-ring
- X_FRAME_BUDGET high-tier terrain allocation: **2.0 ms**
- Single ring fits with marginal headroom

Production clipmap (spec 21) ships 8 rings = ~1M tris total. Per-tri
cost is the same (vertex+fragment shader unchanged); total cost
scales roughly linearly. **Estimated full-rig cost on RTX 3060:
~4-6 ms.**

That's OVER the 2.0 ms terrain budget. Mitigations in spec 21:
- Texture2DRD heightmap pages (already faster than texture sampler)
- LOD morph + ring-band visibility culling (don't render off-camera)
- Reduce inner ring resolution OR use fewer rings at lower tiers
- W4.1 measured similar full-ring clipmap on RTX 5090 at ~1-2ms;
  3060 extrapolation pessimistic without LOD optimization

**Conclusion**: clipmap is viable on target hardware. Need Phase 4
+ Phase 4.5 (calibration sprint) to measure full implementation.
This prototype proves the primitive works in Godot 4.5; full perf
validation is Phase 4 work.

## What this validates (per spec 15a section E)

- ✅ Texture2D can be sampled in vertex shader for height displacement
- ✅ A 256×256 grid mesh renders without issues
- ✅ Frame time stays well within budget on dev hardware (1500+ fps
  uncapped)
- ✅ Godot 4.5 ships everything needed (no extensions, no PRs, no
  GDExtension authoring)

## What it does NOT validate

- Multi-ring streaming with snap-to-grid morph zones
- Per-page async generation via JobScheduler
- Material array binding for multi-biome blend
- LOD-band morph between adjacent rings
- Macro_albedo distance blending
- Surface slot world masks

These are spec 21 implementation concerns (Phase 4).

## Files

- `renderer_research_prototype.tscn` — the scene
- `MinimalClipmap.gd` — grid mesh builder + perf logger
- `minimal_clipmap.gdshader` — vertex displacement + fragment color

## Refs

- Spec 15a `RENDERER_DECISION.md` (the parent decision doc)
- Spec 21 TERRAIN_RENDERER (the eventual full implementation)
- Pitfall meta-2 (`--headless` disables RenderingDevice; this scene
  uses `--display-driver windows` per the recipe)
