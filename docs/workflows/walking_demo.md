# Workflow: Walking Demo

> Phase 4.6 deliverable. Launches the W5 terrain renderer end-to-end
> with a real world bundle. Walk around with WASD.

## Launch

### From command line (recommended for the first run)

```powershell
& "C:\Godot\v4.6.2\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64.exe" --path demo
```

Godot opens the `demo/` project; the main scene
(`res://scenes/walking_demo.tscn`) launches automatically.

### From Godot editor

1. Open `demo/project.godot` in Godot 4.6.2+
2. Press F5 (run main scene)

## Controls

| Input | Action |
|---|---|
| `W` / `A` / `S` / `D` | Walk |
| Mouse | Look (mouse captured at launch) |
| `Space` / `Ctrl` | Fly up / down |
| `Shift` | Sprint (3× speed) |
| `Esc` | Release mouse |
| `Tab` | Toggle mouse capture |
| `F11` | Fullscreen |

Camera starts at (0, 60, 0) — 60 m above the terrain plane.

## What to look for

### Pillar 1 (visual quality)

- **Heightmap displacement**: terrain should NOT be flat — there
  should be visible hills + valleys as you walk
- **LOD morph**: walk across a ring boundary (try sprinting east
  for ~30s) — transitions should be gradual, not popping
- **Macro modulation**: at distance, terrain color should vary
  subtly via the world-noise hash modulation (no macro_albedo PNG
  in this demo bundle; Phase 5 texture pipeline ships the real one)

### Pillar 2 (performance)

- **Sustained 60 fps** during slow walk
- **No long hitches** (>33ms) when entering new pages — the
  bounded-concurrency window (4 in-flight pages, Phase 4.5) should
  cap stall length
- **Continuous sprint** at the world edge: how many seconds of
  motion before frame time degrades? (Calibration measured the
  steady-state churn cost; this is the live-look version)

### Pillar 3 (architecture)

- **No crashes** on Esc → quit
- **No RID leaks** in console output at exit (look for
  `gpu_tracker shutdown — no leaked RIDs`)

## Known limitations (Phase 4.6 scope)

These are NOT bugs; they're explicit-defer items:

- **No real textures**: surface_slots.json has 0 siblings; terrain
  shows the macro-fallback color modulated by world noise.
  Phase 5 (texture pipeline) lights these up.
- **No biome variation**: one biome, one slot. Phase 6 adds the
  second biome + transitions.
- **CPU→ImageTexture per page upload**: each new page does a
  256² float-32 encode loop on the main thread. Phase 5 Texture2DRD
  upload pathway removes this.
- **Render-thread serialization**: page generation does
  `rd.submit() / rd.sync()` on render thread. Concurrent pages serialize
  beyond the bounded-concurrency window's batching benefit. Phase
  5+ async-readback split addresses this.

## Reporting issues

Things to record if the demo misbehaves:

1. Hardware: GPU model, driver version, OS
2. Tier (defaults to `high` = 5 rings)
3. Frame time avg + peak during the misbehavior
4. Console errors / warnings
5. Screenshot of any visual glitch

## Calibration recipe

Run all 5 quality tiers via the demo by editing the TerrainWorld's
`quality_tier_override` property in the scene file (`high` is the
default). Per-tier `terrain_rings` values come from
`engine/resources/quality_tiers.json`:

- low: 3 rings
- medium: 4 rings
- high: 5 rings
- ultra: 6 rings
- cinematic: 7 rings

(All under the 7-ring inflection point observed in Phase 4.5
calibration on RTX 5090 Laptop. RTX 3060 measurements pending
hardware.)

## Doc cap status

~90 lines (under 350 cap).
