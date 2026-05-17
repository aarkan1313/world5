# Phase 4.5 Calibration — Build Note

> Date: 2026-05-17
> Hardware: NVIDIA RTX 5090 Laptop GPU + Godot 4.6.2 stable mono
> Test harness: `engine/tests/perf/test_terrain_calibration_real_device.gd`
> Raw record: `user://_calibration/terrain_1779031427.json`

## What was measured

Per-ring-count CPU frame time during a 60-frame figure-8 camera walk.
Camera at Y=50, horizontal sweep radius 30m. `ring_vertex_grid=64`
(lighter than production 256 so all 5 tier configs run in <30s
combined). Other knobs: `inner_cell_size_m=0.5`, `page_extent_m=32.0`,
`terrain_pages_max=128`.

**What this includes**: TerrainWorld._process tick + JobScheduler
ticks + ResidencyManager diff + observe-from-main of GpuJob
serialization. Page generation is happening continuously (60 frames
of camera motion → constant residency churn).

**What this does NOT include**: pure rendering time without page
streaming. GPU-side per-frame time (Godot 4 dropped the
`RENDER_GPU_FRAME_TIME` monitor; RD timestamp capture is a separate
implementation pass).

## Results (RTX 5090 Laptop, Godot 4.6.2)

| Config        | Rings | CPU avg | CPU peak | Resident pages | full_detail_ready |
|---------------|-------|---------|----------|----------------|-------------------|
| low_4r_64g    | 4     | 4.16 ms | 5.57 ms  | 81             | false             |
| medium_5r_64g | 5     | 4.17 ms | 7.71 ms  | 113            | false             |
| high_6r_64g   | 6     | 6.08 ms | 13.70 ms | 113            | false             |
| ultra_7r_64g  | 7     | 26.93 ms| 50.71 ms | 113            | false             |
| cinematic_8r_64g | 8  | 109.47 ms | 207.18 ms | 113         | false             |

## What the numbers say

**4-6 rings sit in a 4-6ms band on 5090 Laptop** under continuous
streaming load. 7 rings is the cliff (4× cost increase). 8 rings is
catastrophic — the bounded-concurrency window (default 4 in-flight
pages) can't keep up with the outer ring's page demand under
camera motion.

**full_detail_ready=false across all configs** because 60 frames
isn't enough for the streaming pipeline to drain the page queue when
the camera is moving continuously. This is real: at the current
1-page-per-frame steady-state throughput (even with concurrency=4,
the render-thread serialization caps actual completion), worlds with
N rings × M pages can take seconds to fully stream.

**Resident-page count caps at 113** — that's the figure-8 footprint
hitting the LRU budget (`terrain_pages_max=128`); the camera moves
into new pages while the oldest get evicted.

## F2 trigger evaluation (per spec 15a)

Spec 15a F2 trigger: "if 3060 measurement exceeds 1.5 ms / ring for
6-ring full renderer, engage F2 (drop default to 4 rings)."

**5090 Laptop → 3060 extrapolation**: rough 3-4× perf factor for
geometry-bound work (worse than the FLOP ratio because clipmap is
rasterizer-throughput-limited, not compute-limited).

**Projected 3060 numbers**:
- 4 rings: ~13-17 ms avg (target 2.0 ms terrain budget BLOWN by 7×)
- 6 rings: ~18-25 ms avg (blown by 9-12×)
- 8 rings: catastrophic

**This blows the 2.0ms terrain budget at every tier on 3060.** The
measurement is including streaming-under-motion cost; the "no
motion" / cache-hot rendering cost is presumably much lower. But
the figure-8 walk IS the use case spec 21 was budgeted for ("60fps
p99 during walk-mode movement").

**F2 trigger decision**: TBD pending one or more of:
1. Real 3060 hardware measurement (currently unavailable on dev rig)
2. Separating "pure render cost" from "render + streaming" via two
   measurement modes (recommended: camera-stationary vs camera-moving)
3. Phase 4.5+ work on the streaming bottleneck (TR-PERF-C2 was only
   partially addressed by bounded-concurrency window=4; the
   render-thread `submit/sync` serialization is the real cap)

**Interim conservative call**: assume F2 engages on 3060. Document
defaults: 6 rings on 5090-class, 4 rings on 3060-class (set via
quality tier).

## What this calibration sprint did NOT do

- Texture2DRD height_gpu binding (still CPU→ImageTexture per page;
  M2 audit note recommended measuring this specifically — partially
  measured, the encode_float loops are inside the cpu_avg numbers)
- Pure-render-cost isolation (stationary-camera baseline)
- Real RTX 3060 measurement
- Update quality_tiers.json with per-tier ring_count overrides
  (deferred to Phase 4.6 when walking demo provides ground truth on
  visual ring-count requirements)

## Recommended Phase 4.6 entry conditions

1. Add a stationary-camera measurement to isolate pure render cost
   from streaming cost
2. Wire height_gpu Texture2DRD upload to remove the per-page
   CPU→ImageTexture encode bottleneck (M2)
3. Cap `terrain_pages_max` in production at per-tier values informed
   by measurement (4 rings × ~10 pages × tier factor)

## Phase 4.6 stationary-baseline result (2026-05-17)

The stationary baseline measurement (item 1 above) flipped the
diagnosis. See `engine/tests/perf/test_terrain_stationary_real_device.gd`
+ `user://_calibration/stationary_<ts>.json`. Results:

| Rings | Motion avg | Stationary avg | Settled? |
|-------|-----------|----------------|----------|
| 4     | 4.16 ms   | 4.43 ms        | yes (26 frames) |
| 5     | 4.17 ms   | 4.37 ms        | yes (90 frames) |
| 6     | 6.08 ms   | 5.57 ms        | no (>239 frames) |
| 7     | 26.93 ms  | 25.90 ms       | no (>239 frames) |

**Stationary cost ≈ motion cost** at every ring count. The 7→8
cliff is **rasterization-bound**, not streaming-bound. The bounded-
concurrency window fix (TR-PERF-C2 / Phase 4.5) was reasonable
defensive engineering but did NOT address the actual bottleneck.

**Implication**: the render cost itself is what blows the 3060
budget. Going from 7→6→5 rings buys back enough budget; per-tier
`terrain_rings` (3/4/5/6/7 from low to cinematic) per Phase 4.5
close is the right call.

The "settled: false" at 6 + 7 rings is interesting — it means
the streaming pipeline can't fully drain even when the camera is
stationary for 240 frames. That's the LRU thrashing against the
ring footprint OR the bounded-concurrency window starving outer
rings. Worth investigating in Phase 5, but not blocking — the
rendered output is still correct; it's just that not every page in
the footprint is fully resident.
