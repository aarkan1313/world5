# Phase 4.5 — Calibration Sprint

> Phase: Phase 4.5 (between Phase 4.4 close + Phase 4.6 walking demo)
> Status: 🚧 in progress
> Estimated sessions: 1-2
>
> Goal: replace paper perf numbers with measured ones on dev hardware
> (RTX 5090 Laptop). Document the extrapolation factor to RTX 3060.
> Action the deferred TR-PERF criticals from Phase 4.4 audit. Lock
> the F2-trigger evaluation per spec 15a.
>
> Gates Phase 4.6 (walking demo) by establishing whether the 6-ring
> production renderer fits the 2.0ms terrain budget.

## What Phase 4.5 must produce

### 1. Measurement harness
- [ ] `engine/tests/perf/test_terrain_calibration.gd` — measures
      per-frame CPU + GPU time across the 5 quality tiers
- [ ] Runs in `verify --full` capture layer (already wired)
- [ ] Output: JSON record per tier with measured values

### 2. F2-trigger evaluation (per spec 15a OA-S2 fix)
- [ ] Measure 6-ring high-tier on RTX 5090 Laptop
- [ ] Extrapolate to RTX 3060 (~25-30% perf factor)
- [ ] If extrapolated > 1.5 ms: engage F2 (drop default to 4 rings)
- [ ] If F2 itself > 2.0 ms: re-open spec 15a clipmap decision

### 3. Action deferred TR-PERF criticals
- [ ] TR-PERF-C2: async readback split — `rd.submit() / rd.sync()`
      currently blocks render thread, capping streaming at 1
      page/frame. Phase 4.5: split dispatch from readback via per-job
      polling so multiple pages can be in flight on the GPU.
- [ ] TR-PERF-S2: documented above; same fix
- [ ] TR-PERF-S3: MB-based memory budget (not just count); cache
      enforces bytes too, publishes both to StreamingBudget

### 4. quality_tiers.json calibration
- [ ] Replace placeholder `terrain_grid_n`, `terrain_step0_m`,
      `terrain_stepN_m`, `streaming_budget_cpu_pages`,
      `streaming_budget_gpu_pages` with measured/derived values per
      tier
- [ ] Cite Phase 4.5 measurement in `_note`

### 5. X_FRAME_BUDGET.md updates
- [ ] Per-system allocation row for terrain backfilled with measured
      ms (currently placeholder)
- [ ] Calibration date stamp + hardware reference

## Method

1. Write the measurement test with a known camera-motion script
   (figure-8 walk over the world, 600 frames).
2. Record: `Performance.RENDER_GPU_FRAME_TIME`,
   `Performance.RENDER_VIDEO_MEM_USED`, custom timing brackets in
   `TerrainWorld._process` for CPU side.
3. Run across all 5 tiers (low / medium / high / ultra / cinematic)
   by setting `quality_tier_override` per-test.
4. Persist results to `user://_calibration/<date>.json`.
5. Hand-update `quality_tiers.json` + `X_FRAME_BUDGET.md` from the
   JSON.

## Out of scope

- Real RTX 3060 measurement (auditor's recommendation #5 — we run
  on the dev machine; the 3060 extrapolation is the gate). User
  acquires a 3060 → revisit before Phase 6.
- Texture pipeline perf (Phase 5)
- Decoration perf (Phase 7)
- Atmosphere shader cost (Phase 9)

## Close criteria

- [ ] Measurement harness lives in `engine/tests/perf/` + runs green
      in `verify --full` capture layer
- [ ] At least one JSON measurement record exists at
      `docs/build-notes/phase_4_5_calibration_<date>.json`
- [ ] `quality_tiers.json` `_note` updated with measurement date
- [ ] F2-trigger decision recorded in spec 15a (engaged or not)
- [ ] TR-PERF-C2 fix in place (multi-page in-flight)
- [ ] All 5 verify layers green
