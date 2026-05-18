# Spec: Terrain Backend

> Status: shipped (2026-05-18; promoted per spec-to-impl audit — GpuTerrainBackend.gd + TerrainPageRequest/Result + page generation pipeline shipped)
> Tier: 1 (core)
> Depends on: 19_KERNEL_SYSTEM, 07_JOB_SYSTEM, 10_STREAMING_BUDGET, 13_QUALITY_TIERS
> Consumed by: terrain renderer, collision, nav export, decoration generator, AI knowledge

## Purpose

The compute layer that turns kernels into per-page terrain data:
heightmap, collision-height, slope, nav-traversability, biome mask,
density layers. Renderer consumes the GPU-resident pages; gameplay
systems (collision, nav, decoration, AI) consume CPU-resident pages.

W4.1 had three backends (GDScript / C# / GPU compute) coexisting with
an opt-in flag. W5 commits to **one GPU backend (default) + one CPU
fallback (probably C#, decided per renderer research)**. The page
contract is the public surface; backends are interchangeable
implementations behind it.

## Non-goals

- Backends for non-Godot runtimes (we target Godot 4.5)
- Multi-machine page generation (single-machine only)
- Direct kernel sampling from rendering shader (renderer reads
  pre-computed GPU pages; not a per-fragment kernel call)

## Public API (skeleton)

### Page contract

```
TerrainPageRequest:
    world_xz: Vector2       # page origin in world space
    extent_m: float          # page side length
    grid_n: int              # samples per side
    seed: int
    tier: String             # quality tier name
    capabilities: PackedStringArray   # what data the requester needs

TerrainPageResult:
    request: TerrainPageRequest
    height: Texture2DRD | PackedFloat32Array  # GPU page for renderer; CPU array for gameplay
    collision_height: PackedFloat32Array      # CPU, sparse (collision rings only)
    slope: PackedFloat32Array                  # CPU
    nav_traversability: PackedByteArray        # CPU mask
    biome_mask: Texture2DArrayRD | PackedByteArray
    cache_key: String           # content-addressed (see spec 12)
    version_stamp: Dictionary   # per spec 17
```

`request.capabilities` lists what the requester needs. Backend
computes only what's requested, saves work.

**Capability vocabulary** (SA-S3.1; enum enforced by world contract):
- `height_gpu` — `Texture2DRD` height page for renderer sampling
- `height_cpu` — CPU `PackedFloat32Array` height for gameplay queries
- `collision_height` — sparse CPU array, collision rings only
- `slope` — per-cell slope CPU array (used by decoration, nav, roads)
- `nav_traversability` — CPU byte mask (used by spec 33 nav export)
- `biome_mask_gpu` — `Texture2DArrayRD` per-biome weights for shader
- `biome_mask_cpu` — CPU byte indices for decoration placement queries
- `drainage_map` — from ErosionKernel auxiliary output (spec 19);
  GPU `Texture2DRD` for water shaders
- `flow_direction` — from ErosionKernel; CPU array for roads pathing

New capability strings are added per consumer; each consumer's spec
declares which it needs. World contract preflight checks that
requested capabilities are in this vocabulary.

### Backend (single)

V1 ships ONE backend: **`GpuTerrainBackend`** — compute shader,
writes `Texture2DRD` directly for renderer pages; computes CPU-side
slope/nav/collision via the same compute pass + readback for the
sparse subset that gameplay needs.

```gdscript
class_name TerrainBackend extends RefCounted

func generate_page(request: TerrainPageRequest) -> TerrainPageResult
func name() -> String   # "gpu"
```

**No CPU fallback in v1.** Target hardware (RTX 3060 / 4060+) has
Vulkan + Forward+; W5 hard-requires it. Trade-off: W5 can't run on
non-Vulkan systems (Mac without MoltenVK, some Linux setups, very
old hardware). If a future consumer needs broader compatibility, a
pure-GDScript fallback can be added then; the page contract is
already designed to allow swapping backends behind it.

## Producer / consumer contract

- **Produces**: `TerrainPageResult` per request. GPU pages live in
  Godot's render queue; CPU pages are plain arrays.
- **Consumes**: `TerrainPageRequest` from renderer, collision, nav,
  decoration, etc.
- **Page jobs**: all backend work runs through the Job system
  (CPU backend = NORMAL priority worker; GPU backend = render-thread
  queue, not WorkerThreadPool).

## Page cache integration

Generated pages are content-addressed (spec 12). Same `(world_xz,
extent, grid_n, seed, tier, kernel_config_hash)` hits the cache;
re-running a session reuses prior pages without regeneration.

CPU page cache is bounded via streaming budget (`cpu_pages` key).
GPU page cache is bounded via `gpu_pages` key. Both LRU-evicted past
budget.

## Runtime override layer (audit M17)

For runtime deformation (spec 38), each page has a **base + overlay**
pattern:

- **Base page** (immutable, content-addressed): the kernel-generated
  heightmap + biome mask + slope as documented above. Cached per
  spec 12.
- **Overlay page** (mutable, per-session): a sparse delta texture
  storing runtime edits — craters, footprints, magical impacts. Empty
  by default (zero-cost). When deformation is applied, the
  `OverlayApplier` GpuJob (spec 08a) writes the crater profile into
  the overlay texture's RD.

  **Format** (SA-M3.2): R32F single-channel (height delta only;
  positive = raise, negative = lower). 512×512 per active chunk.
  Allocation strategy: per-chunk sparse — overlay texture is only
  allocated when a deformation first writes to that chunk; freed
  when `sum(abs(delta)) < epsilon` (default 1e-3 m total mass) for
  N seconds (default 5s) of no writes. Quiescent chunks point at a
  shared zero-overlay sentinel texture (single allocation reused).

Final sampled height = `base.height + overlay.height`. Shader does
the add in one fetch. Overlay texture is small (uses a sparse
allocation strategy: only chunks with active overlays allocate a
512×512 GPU page; quiescent chunks point at a zero texture).

Overlay lifecycle:
- Allocated on first deformation in the chunk
- Freed when overlay returns to zero (last deformation reverted) OR
  on world unload (ephemeral per spec 38 v1)
- Persistent overlays (consumer-driven save) handled by spec 39
  applying overlay snapshots at load time

The overlay layer is **GPU-resident only** (per rule 2 of spec 08a;
gameplay reads CPU TerrainPageResult capabilities that include
deformation-aware slopes via explicit CPU readback after deformation
job completes).

## Dependencies

- `19_KERNEL_SYSTEM` (backends call kernels to compute fields)
- `07_JOB_SYSTEM` (all backend work is jobs)
- `10_STREAMING_BUDGET` (page cache size + concurrent job count)
- `13_QUALITY_TIERS` (per-tier page resolution, grid_n, etc.)
- Godot 4.5 `RenderingDevice` for GPU backend

## Quality bar

- GPU backend generates 256×256 page in < 10ms on RTX 3060
- CPU backend generates 256×256 page in < 200ms on dev CPU (parity
  fallback, not perf target)
- Cross-backend parity: GPU and CPU produce heightmaps within 1e-4 m
  (floating-point rounding tolerance)
- Cache hit returns in < 1ms (lookup only)
- 100% test coverage: pytest + gut + GPU compute spike harness

## Discoverability

- **Entry point**: `TerrainBackendAdapter.generate_page(request)` from
  any consumer
- **Schema**: `TerrainPageRequest` + `TerrainPageResult` field shapes
  documented above; full Resource definitions in
  `engine/scripts/terrain/backend/`
- **Validator / preflight**: world contract checks backend availability;
  parity harness verifies GPU↔CPU match
- **Example**: `engine/examples/terrain_backend_example.tscn` requests
  a single page + visualizes the result
- **Deterministic outputs**: yes (same request → same content-addressed
  key → same result)

## Open questions

- **Cross-backend parity testing**: when there's only one backend
  (GPU), there's nothing to test parity AGAINST. The pytest GPU
  parity harness from W4 doesn't apply here. Test plan: validate GPU
  output against a reference deterministic Python implementation of
  the kernels (which runs CPU-only and is treated as the "ground
  truth" for testing only, not a shipping backend).
- **Density layers**: W4.1 had `gentle_surface`/`steep_surface`/
  `biome_transition` density layers added speculatively for future
  nav/decor consumers. **Dropped from W5**: no consumer ever used
  them. If a future system needs them, add at that point.
- **Capabilities filtering**: `request.capabilities` is in the schema
  but the exact key set is per-consumer-driven. Spec'd in plan doc.

## References

- W4.1 `scripts/terrain_backend/`, `scripts/csharp/worldgen/`,
  `scripts/worldgen/WorldGenBackendAdapter.gd` — proven backend
  abstraction
- W4.1 memory entry `w4_gpu_cpu_contract_2026_05_14` — the
  GPU/CPU separation rule

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (M17). Documented runtime override layer
  (base + overlay pattern) that spec 38 RUNTIME_DEFORMATION assumes.
  GPU-resident only, sparse, lifecycle tied to overlay non-zero state.
