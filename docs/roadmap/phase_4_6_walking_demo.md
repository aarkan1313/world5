# Phase 4.6 — Walking Demo

> Phase: 4.6 (final sub-phase of Phase 4 terrain MVP)
> Status: 🚧 in progress
> Estimated sessions: 1-2

Goal: prove the terrain renderer end-to-end with a real world bundle
+ scene the user can launch + walk. Close out the Phase 4 audit-
deferred items.

## Deliverables

### World bundle: `engine/worlds/walking_demo/`
- [ ] `kernels/noise_stack.json` — fBm params (modest amplitude + freq)
- [ ] `macro_albedo.json` + procedural placeholder (no PNG yet; the
      texture-pipeline output goes here in Phase 5)
- [ ] `surface_slots.json` — placeholder (1 slot for now; biome
      catalog spec 22 not exercised until Phase 6 second biome)

### Demo scene: `demo/scenes/walking_demo.tscn`
- [ ] TerrainWorld at default high tier (5 rings post-calibration)
- [ ] WalkCamera (FPS-style: WASD + mouse look)
- [ ] DirectionalLight3D (sun-like)
- [ ] WorldEnvironment (procedural sky)

### Stationary-camera baseline (audit-deferred from Phase 4.5)
- [ ] `engine/tests/perf/test_terrain_stationary_real_device.gd` —
      measure pure render cost with no streaming churn
- [ ] Compare against Phase 4.5 motion baseline to isolate streaming
      bottleneck cost
- [ ] Update build-note + spec 15a with the cleaner number

### Walk-through doc
- [ ] `docs/workflows/walking_demo.md` — launch command + WASD
      controls + what to look for (LOD pop, repeat, hitches)
- [ ] User runs it; reports back; we iterate

### Visual review at each tier (low/medium/high/ultra)
- [ ] Launch with each tier override
- [ ] Subjective: does 3-ring low actually look acceptable? Does
      ultra justify the +2 rings?
- [ ] If "low looks bad" → revisit calibration tiers

## Out of scope (defer to Phase 5+)

- Real ground textures (Phase 5 texture pipeline produces these)
- Sibling/detail variety (spec 24 Layer 1/2 — deferred per Phase 5)
- Texture2DRD upload pathway (audit M2; needed but the entire spec 08a
  GPU path on the renderer side is its own refactor — likely Phase 5
  alongside texture pipeline since both touch RD heavily)
- Real RTX 3060 measurement (still no hardware)

## Close criteria

- [ ] User can launch the demo + walk around with WASD
- [ ] At least one screenshot in the build-note
- [ ] Stationary baseline measured + recorded
- [ ] All 5 verify layers stay green
- [ ] Phase 4 closes (ROADMAP row → ✅ done)

## Doc cap status

~80 lines (under 350 cap).
