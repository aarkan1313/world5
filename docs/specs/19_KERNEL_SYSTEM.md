# Spec: Kernel System

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — NoiseStackKernel + ErosionKernel + KernelComposer + bake_page Python end-to-end)
> Tier: 1 (core)
> Depends on: 01_MODULE_LAYOUT, 13_QUALITY_TIERS
> Consumed by: terrain backend, materials, nav, climate

## Purpose

Pure-function generators of world data at arbitrary world XZ. Given
`(world_x, world_z, seed)`, a kernel returns one or more scalar fields:
height, biome weights, slope, moisture, temperature, etc.

The kernel system is the **mathematical truth** of W5's worlds. The
terrain renderer samples it to display geometry; nav samples it to
extract walkable surfaces; materials sample it to choose textures.
Everything downstream is a view onto the kernel output.

W4.1 had this (`pipeline/kernels/` + `scripts/kernels/`) with one
implementation: `NoiseStackKernel` (fBm). Python ↔ GDScript ↔ C# /
GPU cross-impl parity tested. Proven pattern.

W5 keeps the shape, expands the kernel family: noise stack, erosion
(hydraulic + thermal — post-process kernel that operates on a height
field produced by another kernel), DEM-feature-driven, astro/lunar
(crater-field), and per-world custom kernels via the composer.

## Non-goals

- Runtime kernel switching (per-world kernel is set at bundle creation;
  changing it requires a re-bake)
- Kernel authoring UI (JSON config + code; no GUI)
- Procedural kernels that depend on global state (kernels are pure
  functions of `(x, z, seed)` plus their config)

## Public API (skeleton — drilled down in implementation plan)

### Python: `pipeline/kernels/`

```python
class Kernel(ABC):
    def sample_height(self, x: float, z: float, seed: int) -> float: ...
    def sample_biome_weights(self, x: float, z: float, seed: int) -> dict[str, float]: ...
    def sample_slope(self, x: float, z: float, seed: int) -> tuple[float, float]: ...
    # other sample_* per kernel capability

class KernelComposer:
    """Blends per-biome kernels via softmax over biome_weights from
    biome catalog. Produces unified (height, weights) at any (x, z)."""
```

### GDScript: `engine/scripts/terrain/kernels/`

Mirror API. Cross-impl parity tested.

### Kernel types shipped in v1

Three kernels in v1, in build order:

1. **`NoiseStackKernel`** — fBm-based, W4.1's proven kernel.
   Carry-over with refactor. Sprint 1 (smallest, validates the kernel
   contract).
2. **`ErosionKernel`** — hydraulic + thermal erosion. **Pre-bake
   global pass, not per-page** (audit S13): erosion is intrinsically a
   whole-world simulation (water flows downhill across the entire
   world), so running it per-chunk would seam at chunk borders. The
   erosion runs once at world bake time over the full world's height
   field (or feathered overlap regions for incremental bakes), output
   is cached per spec 12 content addressing, and runtime samples the
   pre-eroded field. Sprint 2. References Mei et al. 2007 (hydraulic)
   and Musgrave/Kolb (thermal). GPU compute version is the primary
   path; CPU pure-Python version for parity reference.

   **World-size bound (SA-S2.12)**: full-world pre-bake erosion
   has a hard cap of **10km × 10km** at 2m resolution (= 25M samples,
   ~100 MB float heightfield, fits comfortably in 8 GB GPU memory
   with several iteration buffers). Worlds larger than 10km × 10km
   must use the **feathered tile-with-overlap** pre-bake mode:
   erosion runs on 5km × 5km tiles with 500m overlap on each edge;
   overlap regions blend at tile boundaries. Tile mode adds bake
   time + minor seam risk (acceptable since erosion at large scale
   is gentle). Spec'd cap; consumer worlds > 10km × 10km opt into
   tile mode explicitly.

   **Auxiliary outputs (SA-C4.8 fix)**: the hydraulic pass naturally
   computes water flow as it iterates. ErosionKernel exposes:
   - `drainage_map`: per-cell accumulated water flow magnitude (used
     by spec 35 water for river mask derivation)
   - `flow_direction`: per-cell flow direction vector (used by
     spec 35 for river flow-shader direction; used by spec 41 roads
     to bias paths along valleys)
   - `flow_accumulation`: per-cell upstream area (helps distinguish
     "tiny stream" from "major river" for spec 35 width derivation)
   Saved alongside the eroded heightmap; cached together; no
   separate kernel needed. Spec 35 (water) and spec 41 (roads)
   document their consumption.
3. **`DemFeatureKernel`** — extracts ridge / drainage / aspect features
   from a real DEM and uses them as a procedural basis (so the
   resulting worlds feel grounded in real geology without being
   recognizable as the source DEM). Sprint 3. W4.1 wished for this,
   never built it. **DEM source handling defined upfront** (audit
   S13): consumer-supplied DEM at `worlds/<world>/dem/`, schema in
   `engine/resources/schemas/kernels/dem_source.schema.json` (bounds
   in lat/lon + projection EPSG + resolution + file format
   GeoTIFF/NPZ). World contract validates the DEM source against
   declared elevation range.

**Deferred** (schema-slot only; no implementation):

- `AstroKernel` — crater fields, lunar maria patterns. Built when a
  consumer needs planetary worlds. The kernel contract is generic
  enough that adding this later doesn't require core changes.

## Producer / consumer contract

- **Produces**: height field + biome weights + slope (and per-kernel
  extras like moisture, climate) at any (x, z, seed)
- **Consumes**: per-biome kernel config (noise_stack params, erosion
  params, etc.) from biome catalog

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `13_QUALITY_TIERS` (kernels may have per-tier complexity knobs —
  e.g. octave count for fBm)

## Quality bar

- **Cross-impl parity (within-tier)**: Python (pipeline reference)
  ↔ GPU compute (runtime hot path) produce identical outputs (max
  delta < 1e-5 m for height; exact match for biome weights) at the
  SAME tier. GDScript + C# parity removed per audit C4 — spec 20
  ships ONE backend (GPU), and the Python implementation is the
  ground-truth parity reference for the GPU implementation. Not a
  shipping backend.
- **Cross-tier**: outputs may differ across tiers by design (fBm
  octave count differs; erosion iteration count differs). Parity is
  within-tier only. Audit M5.
- Single sample (Python, parity reference only — NOT a hot path):
  any time. Python is not the runtime path so its single-sample
  perf is moot. Pipeline bake throughput target: full world
  (1km × 1km, 4-byte float) baked in ≤ 60s on dev hardware.
- Full chunk sample (256×256 grid) on GPU backend: < 10ms on RTX 3060
- Deterministic: same (x, z, seed, config, tier) always produces same
  output
- 100% test coverage of every shipped kernel (pytest GPU↔Python parity)

## Discoverability

- **Entry point**: `KernelComposer(catalog)` — construct from biome
  catalog; sample at arbitrary (x, z)
- **Schema**: per-kernel config schema in `engine/resources/schemas/kernels/`
  (noise_stack.schema.json, erosion.schema.json, etc.)
- **Validator / preflight**: world contract checks kernel configs
  parse + produce bounded heights for declared elevation range
- **Example**: `pipeline/kernels/examples/` shows each kernel type in
  isolation; W5 demo world combines them via composer
- **Deterministic outputs**: yes, by definition (pure functions)

## Open questions

- **GPU implementation parity**: NoiseStack ships GPU compute (hot
  path). Erosion runs as a pre-bake pass (above; GPU compute primary,
  Python parity reference). DemFeature runs on CPU only at bake time
  (it's a feature-extraction pass over a pre-loaded DEM; not a
  per-fragment cost; cached per spec 12).
- **Per-world custom kernels**: can a world bundle ship its own
  kernel `.gd`/`.py` file? Probably yes (consumer extension hook);
  defer specifics.

## References

- W4.1 `NoiseStackKernel`, `KernelComposer`, cross-impl test
- WISHLIST "Erosion (heightmap pre-process) — hydraulic + thermal"
- WISHLIST "Astro / moon / lunar / planetary sources"

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (C4, S13, M5). Parity bar: Python ↔ GPU only
  (GDScript + C# removed; spec 20 ships only GPU). Erosion: pre-bake
  global pass (not per-page; per-page would seam). DEM source handling
  defined upfront. Cross-tier parity clarified (within-tier only).
- 2026-05-16: post-self-audit (SA-C4.8). ErosionKernel exposes
  drainage_map + flow_direction + flow_accumulation as auxiliary
  outputs (consumed by spec 35 water + spec 41 roads). Closes
  silent contract gap.
- 2026-05-17: audit C4. Phase 4.3 shipped NoiseStackKernel ONLY;
  v1 also requires ErosionKernel + DemFeatureKernel + KernelComposer
  which are unscheduled in the original ROADMAP. Scheduled as
  **Phase 5.7 erosion sprint** (ErosionKernel + KernelComposer);
  DemFeatureKernel deferred to dedicated later sprint (no immediate
  Phase 6+ consumer). ErosionKernel MUST ship before Phase 10 water.
