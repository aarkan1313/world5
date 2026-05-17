# Phase 4.6 Walking Demo — Build Note

> Date: 2026-05-17
> Closes Phase 4 (Terrain MVP)

## What shipped

### World bundle
- `engine/worlds/walking_demo/kernels/noise_stack.json` — fBm with
  50m amplitude + 512m base wavelength
- `engine/worlds/walking_demo/surface_slots.json` — placeholder
  (1 slot, 0 siblings; Phase 5 texture pipeline fills these)
- (no macro_albedo.json or PNG — fallback color + world-noise modulation
  is the visual today; Phase 5 wires the real macro)

### Demo scene
- `demo/scenes/walking_demo.tscn` — TerrainWorld + WalkCamera +
  DirectionalLight3D + WorldEnvironment (procedural sky)
- `demo/scripts/WalkCamera.gd` — WASD + mouse-look FPS camera with
  sprint + fly modes
- `demo/project.godot` main_scene set to the walking demo

### Stationary-camera baseline (Phase 4.5 audit-deferred)
- `engine/tests/perf/test_terrain_stationary_real_device.gd` — measures
  pure render cost with camera parked
- Result: **stationary cost ≈ motion cost** at every ring count
- Flipped the Phase 4.5 hypothesis: bottleneck is **rasterization**,
  not streaming. The bounded-concurrency window fix was sound
  defensive engineering but addressed the wrong layer
- Spec 15a + build-notes/phase_4_5_calibration_2026_05_17.md updated
  with the cleaner readout

### Walk-through doc
- `docs/workflows/walking_demo.md` — launch command + controls +
  what to look for at each pillar + known limitations

## How to run

```powershell
& "C:\Godot\v4.6.2\Godot_v4.6.2-stable_mono_win64\Godot_v4.6.2-stable_mono_win64.exe" --path demo
```

Main scene launches automatically. WASD to walk; ESC to release
mouse; Shift to sprint.

## What does NOT ship in Phase 4.6 (explicit defer to Phase 5+)

| Item | Phase | Why |
|------|-------|-----|
| Real ground textures | 5 | Texture pipeline produces them |
| Sibling/detail variety | 5 | Spec 24 Layer 1/2 (per Phase 5 amendment) |
| Texture2DRD upload pathway | 5 | Bigger refactor; touches spec 08a contract on the renderer side |
| Render-thread submit/sync split | 5+ | Stationary baseline showed this isn't the actual bottleneck — deprioritized |
| Real RTX 3060 measurement | when hardware | Auditor recommendation #5; no 3060 on dev rig |
| Per-tier visual review | next session | User runs each tier + reports back; bundle config tweaks follow |

## Pillar status at Phase 4 close

| Pillar | Status |
|---|---|
| 1 Visual quality | ⚠️ Partial — heightmap displacement + lighting work; no ground textures yet (Phase 5); no sibling variety; macro fallback color only |
| 2 Performance | ⚠️ Measured 4-6 ms on 5090 Laptop at 4-6 rings; F2 engaged on 3060 estimate (real 3060 measurement pending hardware) |
| 3 Architecture | ✅ TerrainWorld 426/800 lines; module decomposition clean; 270+ tests across 5 verify layers; 2 audit passes actioned |
| 4 Time-to-ship | ✅ No shortcuts taken; calibration sprint ran; audit findings actioned in full |

## Open items rolled to Phase 5

1. Texture pipeline produces real sibling sets + detail array +
   macro_albedo PNG → variety Layers 1/2/3 light up
2. Texture2DRD upload pathway in MaterialPipeline.bind_height_map_rd
   (today: CPU→ImageTexture per page)
3. Spec status sweep (all 48 specs still `draft`)
4. Per-tier walking-demo visual review (user-facing)

## Verify status

5/5 layers green stable on Godot 4.6.2 stable mono:
- pytest 115 passed
- gut (headless) all passed
- gut_real_gpu including new stationary baseline — all passed
- preflight 0 errors / 0 warnings
- capture all passed

Total wall-clock: ~42s (calibration + stationary baseline dominate
real-GPU layer at 34s combined).
