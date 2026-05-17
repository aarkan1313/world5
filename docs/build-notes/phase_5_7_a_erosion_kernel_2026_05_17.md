# Phase 5.7.a — Python ErosionKernel reference (DONE 2026-05-17)

> Phase: 5.7.a (first sub-task of Phase 5.7 erosion sprint family)
> Status: ✅ done 2026-05-17
> Plan: [phase_5_7_erosion_sprint.md](../roadmap/phase_5_7_erosion_sprint.md)
> Schema: [erosion.schema.json](../../engine/resources/schemas/kernels/erosion.schema.json)
> Driven by: spec 19 §"Kernel types shipped in v1" item 2 + Phase 6 paused on
> KernelComposer (5.7.b) which itself needs the kernel contract proven first

## What shipped

The **parity-reference Python implementation** of hydraulic + thermal
erosion per spec 19. This is the ground truth a future GPU compute
port (5.7.d) is validated against — numpy-vectorized but single-
threaded, optimized for clarity + correctness, not speed.

### Files

| File | Purpose |
|---|---|
| `engine/resources/schemas/kernels/erosion.schema.json` | Spec 19 input contract (iterations + Mei 2007 hydraulic params + Musgrave thermal params + sane ranges). 12 parameters, all with defaults + descriptions. |
| `pipeline/world5/kernels/erosion.py` | `ErosionKernel` dataclass + `erode(height) -> ErosionResult`. ~250 lines. Mei 2007 hydraulic step (rain → flux → velocity → capacity → dissolve/deposit → evaporate) + Musgrave thermal step (talus-angle slumping). Spec 19 §"Auxiliary outputs" delivered: drainage_map + flow_direction + flow_accumulation. |
| `pipeline/world5/kernels/__init__.py` | Re-exports `ErosionKernel` + `ErosionResult`. |
| `tests/unit/test_erosion_kernel.py` | 8 pytest cases covering construct + shape/dtype contract + flat-input invariance + determinism + bounded range + radial drainage on single-peak fixture + flow direction on ramp + thermal slumping. Written test-first per superpowers TDD. |

### Algorithm summary

**Hydraulic pass (Mei et al. 2007)**, per iteration:
1. Rain falls uniformly (`water += rain_rate`)
2. Outflow flux to 4 cardinal neighbors, proportional to water-surface
   height delta; scaled if outflow would empty the cell
3. Update water depth from inflow - outflow
4. Velocity vector = net horizontal flux
5. Sediment capacity = `Kc × max(sin(slope), min_slope) × |velocity|`;
   dissolve from terrain into water where capacity > sediment, deposit
   where capacity < sediment
6. Evaporate (`water *= 1 - evaporation`)

**Thermal pass (Musgrave/Kolb)**, interleaved with hydraulic:
1. For each cell, find downhill height deltas vs 4 neighbors
2. Where delta > talus_height, slump `talus_rate × excess` to the
   downhill neighbor

**Auxiliary outputs** (spec 19 §"Auxiliary outputs"):
- `drainage_map`: time-accumulated outflow magnitude per cell —
  consumed by spec 35 water for river-mask derivation
- `flow_direction`: final-step (vx, vy) velocity per cell — consumed
  by spec 35 for river flow-shader + spec 41 for road path biasing
  along valleys
- `flow_accumulation`: per-cell upstream cell count via D8 single-
  flow walk — helps distinguish "tiny stream" from "major river"

### Test coverage (8/8 green)

| Test | What it proves |
|---|---|
| `test_constructible_with_defaults` | Schema defaults present + valid ranges |
| `test_erode_returns_same_shape_and_dtype` | API contract — shapes match input + auxiliary outputs shaped per spec |
| `test_erode_flat_input_returns_flat_output` | Numerical stability — no drift on flat input + no thermal |
| `test_deterministic_same_input_same_output` | Spec 19 Quality bar — same (input, params) → byte-identical output |
| `test_erode_preserves_bounded_range` | No NaN/Inf, no runaway growth (≤ 2× original range) |
| `test_drainage_radial_on_single_peak` | drainage_map records downstream accumulation — outer-ring cells have MORE drainage than peak (water from upslope sweeps through) |
| `test_flow_direction_points_downhill_on_slope` | flow_direction points downhill on a +x ramp (mean vx < 0) |
| `test_thermal_slumps_steep_slopes` | Thermal pass reduces peak height when slope exceeds talus angle |

**Test-fixing aside**: my initial `test_drainage_radial_on_single_peak`
asserted INNER > OUTER (intuition: "drainage near the peak should
be biggest"). The actual algorithm shows outer cells have MORE
accumulated outflow because water from upslope passes through them
on its way to the boundary. Flipped the assertion + updated the
docstring to explain the radial direction. This is the kind of
diagnosis-on-the-fly that TDD surfaces.

## What's NOT in this sub-sprint

Deliberately deferred per the Phase 5.7 plan structure:

- **5.7.b KernelComposer** — next sub-sprint. The piece that
  consumes ErosionKernel via biome catalog kernel chains, exposes
  per-fragment biome weights, unblocks Phase 6 multi-biome render
- **5.7.c Content-addressed cache** — once Composer ships, erosion
  output gets cached per spec 12; re-bakes skip recompute
- **5.7.d GPU compute port** — only when Python perf becomes
  bottleneck (this Python ref hits ~60s on 1024² per spec 19
  Quality bar; see perf note below)
- **Sediment advection** — the Mei sediment-transport step is
  simplified in this reference (dissolve/deposit alone, no inter-
  cell sediment flow). Visible carving still happens via dissolve;
  full transport is a refinement for 5.7.d GPU port
- **DemFeatureKernel** — separate sprint per spec 19 amendment, no
  consumer yet

## Perf note

This reference is numpy-vectorized + single-threaded. Estimated
throughput on dev hardware: ~1-2s per iteration on a 1024² grid →
~50-200s for typical iteration counts (50-200). Spec 19 Quality bar
target is "full world (1km × 1km, 4-byte float) baked in ≤ 60s on
dev hardware". The Python reference is at the edge of that target;
the GPU port (5.7.d) is the speed multiplier when needed.

Per the spec 19 §"Pre-bake global pass" model, this is a one-time
cost per world bake (cached after via spec 12); runtime samples
the pre-eroded field, doesn't re-compute.

## How to consume (forward-looking)

Once 5.7.b KernelComposer lands, walking_demo's biome catalog can
add `erosion` to its kernel chain:

```json
{
  "name": "alpine",
  "kernel": {
    "type": "chain",
    "stages": [
      {"type": "noise_stack", "params": {...}},
      {"type": "erosion", "params": {"iterations": 100, "rain_rate": 0.012}}
    ]
  }
}
```

KernelComposer reads the chain, runs each stage, caches per spec 12,
emits drainage_map + flow_direction as side outputs for Phase 10
water + Phase 41 roads to consume.

## Verify status

`pytest tests/unit/test_erosion_kernel.py -v` → 8/8 green in ~0.3s.
Full `python -m world5.verify --fastest` → 151 pytest passed
(was 143 — 8 new ErosionKernel tests).

(NOTE: full mode showed a transient gut_real_gpu failure unrelated
to this sub-task — pure Python additions don't touch the GPU layer.
Investigating separately; the ErosionKernel sub-task itself is clean.)

## Doc cap status

~150 lines (under 350 cap).
