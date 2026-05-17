# Phase 5.7 — Erosion Sprint (ErosionKernel + KernelComposer)

> Phase: 5.7 (sprint-family — multi-session)
> Status: 🚧 planning 2026-05-17
> Driven by: audit C4 + spec 19 v1 §"Kernel types shipped in v1"
> Closes (when fully done): audit C4 (partial — DemFeatureKernel
> deferred to dedicated sprint per spec 19 amendment)
> Required by: Phase 10 water (consumes ErosionKernel `drainage_map`
> + `flow_direction` + `flow_accumulation` per spec 35)

## Why this exists

Spec 19 v1 ships 3 kernels: NoiseStackKernel (✅ done, Phase 4.3),
ErosionKernel (pending), DemFeatureKernel (pending). KernelComposer
binds them into per-world chains. **Only NoiseStackKernel exists in
W5 today** — the rest is spec-only. ErosionKernel is the load-bearing
piece because:

- It gives terrain real geological shape (valleys, ridges, drainage
  patterns) instead of pure-noise hills
- Its auxiliary outputs (`drainage_map`, `flow_direction`,
  `flow_accumulation`) are the **only** input Phase 10 water (rivers,
  lakes) can consume per spec 35
- Without it, terrain quality stalls at "fBm hills" forever — every
  later biome is just colored fBm

KernelComposer makes per-biome kernel chains (noise → erosion →
post-process) possible, which is the spec 22 biome catalog's
intended use.

## What's NOT in this phase

- **DemFeatureKernel** (spec 19 Sprint 3). Deferred to its own sprint
  family. No Phase 6+ consumer needs it yet — it lights up when a
  consumer wants worlds grounded in real DEM source. Phase 5.7 can
  ship without it.
- **Runtime erosion sim**. Per spec 19 §"Pre-bake global pass, not
  per-page": ErosionKernel runs at world-bake time only, output is
  content-addressed (spec 12) and cached. Runtime samples the
  pre-eroded field via the existing terrain backend. No runtime
  compute.
- **AstroKernel + future kernels**. Schema-slot only.

## Sub-sprint structure

Five sub-sprints, each shippable independently. Building the Python
reference first (Sprint 2a) before the GPU compute (Sprint 2b) is
the deliberate inversion of "GPU-first" — the parity-reference
Python impl is the **ground truth** the GPU impl is tested against
(per spec 19 Quality bar). Without the reference, the GPU impl has
nothing to validate against.

### 5.7.a — Python ErosionKernel reference (pipeline-side)

**Scope**: pure-Python implementation of hydraulic + thermal
erosion per Mei et al. 2007 (hydraulic) + Musgrave/Kolb (thermal).
Single-threaded numpy is fine — this is the parity reference, not a
hot path.

**Acceptance**:
- `pipeline/kernels/erosion_kernel.py` shipped
- Input: height field (np.ndarray), iteration count, hydraulic +
  thermal params (rain rate, sediment capacity, evaporation, etc.)
- Outputs: eroded height field + `drainage_map` + `flow_direction`
  + `flow_accumulation` (per spec 19 §"Auxiliary outputs")
- Pytest coverage: deterministic given (seed, input, params);
  output bounds preserved; drainage_map / flow_accumulation produce
  expected shapes
- Example fixture: erode a known-shape input (single peak), assert
  drainage flows radially outward; assert eroded peak is shorter
  than input peak

**Effort**: 3-5 sessions (literature → numpy impl → tests + fixture
validation)

### 5.7.b — KernelComposer (Python + GDScript)

**Scope**: chain composer per spec 19 §"KernelComposer". Reads
biome catalog kernel chains (e.g. alpine = noise → erosion); samples
the composed result at arbitrary (x, z). Bakes the per-biome chain
at world-bake time + caches the output.

**Acceptance**:
- `pipeline/kernels/composer.py` (Python reference)
- `engine/scripts/terrain/kernels/Composer.gd` (GDScript runtime —
  reads from cached output, doesn't re-compute)
- Biome catalog schema extended with per-biome kernel chain spec
  (composer reads + validates against schema)
- Cross-impl tested (Python composer output == GDScript composer
  reading cached output)
- Example: walking_demo's alpine biome's noise-only kernel chain
  validates as a single-kernel chain through the composer (sanity
  check that the composer is back-compatible with current
  noise-only worlds)

**Effort**: 2-3 sessions

### 5.7.c — Cache integration (spec 12 content addressing)

**Scope**: ErosionKernel output is cacheable per spec 12. Per
spec 19: "output is cached per spec 12 content addressing, and
runtime samples the pre-eroded field". This sub-sprint wires the
content-addressed store so re-baking a world doesn't re-run erosion
unless inputs changed.

**Acceptance**:
- ErosionKernel output keyed by content-address of (input height
  + params + seed)
- Re-bake with no input change → cache hit, no compute
- Re-bake with any input change → cache miss, full re-compute
- Cache eviction tested (bounded by spec 12 cache size limits)

**Effort**: 1-2 sessions

### 5.7.d — GPU compute ErosionKernel (engine-side, optional)

**Scope**: port the Python reference to a Godot compute shader for
production bake-time speed. Tested against Python reference for
within-tier parity per spec 19 Quality bar.

**Acceptance**:
- `engine/shaders/kernels/erosion_kernel.glsl` (compute shader)
- `engine/scripts/terrain/kernels/ErosionKernel.gd` (GPU dispatcher)
- GPU output matches Python reference within 1e-5 m max delta at
  the same tier
- 1024² grid eroded in ≤ 60s (within spec 19 bake throughput target)
  on dev hardware
- Cross-impl parity test in `engine/tests/visual/` (real-GPU)

**Effort**: 4-6 sessions (GPU porting is the heavy lift; Mei
algorithm has multiple iteration buffers — flow + sediment + water +
height — each a Texture2DRD per spec 21 GPU-first contract)

**Why "optional"**: if Sprint 5.7.a Python performance is acceptable
for the world sizes shipped (10km² hard cap per spec), GPU port can
be deferred. Most worlds may only need a few minutes of bake time;
the GPU is the speed multiplier when many worlds are baked or when
larger sizes are needed.

### 5.7.e — DemFeatureKernel deferred

Out of scope. Stub spec sections remain; implementation when a
consumer needs DEM-grounded worlds (no Phase 6+ user today).

## Sub-sprint dependencies

```
5.7.a (Python reference) ──────────┐
                                   ↓
                       5.7.b (KernelComposer)
                                   ↓
                       5.7.c (cache integration)
                                   ↓
                       5.7.d (GPU compute) — optional
```

5.7.a is the prerequisite for everything (composer needs SOMETHING
to compose; cache needs SOMETHING to cache; GPU needs SOMETHING to
parity-check against).

## What this phase unlocks

| Downstream | Unblocked because |
|---|---|
| **Phase 10 water (lakes + rivers)** | Spec 35 consumes `drainage_map` + `flow_direction` + `flow_accumulation` for river masks + flow direction shader. Pre-5.7, water can ship lakes only (no rivers). |
| **Phase 6 forest (richer terrain shape)** | Forest biomes can use erosion chains for valley + ridge structure, making the biome feel geologically real vs "noise hills with forest texture". |
| **Phase 41 roads (path biasing along valleys)** | Spec 41 roads bias paths toward `flow_direction` valleys (cheaper to travel along drainage). Pre-5.7, road placement is geometric-only. |
| **DemFeatureKernel future sprint** | Composer + cache + GPU contract all proven against ErosionKernel first. DemFeatureKernel slots into the same framework. |

## Close criteria

5.7 is "fully done" when:
- 5.7.a + 5.7.b + 5.7.c all shipped (5.7.d optional based on perf)
- Walking demo's biome catalog amended with an erosion chain on
  the alpine biome → re-bake produces visibly eroded terrain
  (valleys + ridges instead of pure noise)
- 5/5 verify layers green
- Build note `phase_5_7_close_2026_05_XX.md`
- ROADMAP + STATE updated
- Spec 19 + 35 + 41 cross-references updated to reflect what
  ErosionKernel actually emits + what consumers use

## Risk register

- **Numpy perf**: 1024² erosion may take minutes per iteration;
  100+ iterations could exceed bake throughput target. Mitigation:
  use scipy.ndimage convolutions instead of nested-loop diffs;
  vectorize the Mei flow update. If still too slow, accelerate
  via numba JIT (already in dev requirements) before going GPU.
- **Memory cost**: 10km² @ 2m = 25M floats × 6+ iteration buffers
  ≈ 600 MB during bake. Within spec 19 §"World-size bound" envelope
  but tight. Mitigation: tile mode (spec 19) when memory pressure
  hits.
- **Cross-tier kernel-config drift**: spec 19 Quality bar says
  cross-tier outputs differ by design (octave count, iteration
  count). Risk: tiers diverge too much, walking-demo at low tier
  reads as a completely different shape than ultra. Mitigation:
  per-tier configs share the same "shape" parameter; only
  detail-level parameters vary across tiers.

## Doc cap status

~170 lines (under 350 cap).
