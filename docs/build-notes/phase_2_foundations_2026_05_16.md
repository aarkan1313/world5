# Build-Note: Phase 2 Foundations — 2026-05-16

> Append-only diary entry per spec 02 R6. What shipped, deviations,
> lessons, open follow-ups.

## What shipped

All 13 Tier 0 cross-cutting primitives in code, plus the verify CLI +
preflight + plugin wiring. Single sitting; ~12 commits.

| Sub | System | Tests | Commit |
|---|---|---|---|
| 2.1 | Test infrastructure (pytest + gut + verify CLI) | 4+3 | bcb1d62 |
| 2.2 | Log + World5 singletons (+ Python mirrors) | 11+9 | dec170c |
| 2.3 | QualityTiers + cross-impl parity | 12+9 | 62b84bd |
| 2.4 | Job + JobScheduler | 0+14 | 0d48088 |
| 2.5 | GpuJob + GpuResourceTracker (class shape) | 0+11 | 54b09b2 |
| 2.6 | SpatialIndex (Python + GDScript) | 20+17 | d729b2a |
| — | Real-GPU test infrastructure (user-prompted) | 0+3 | cbf2ada |
| — | USAGE.md + 2 workflow recipes (user-prompted) | 0+0 | be56e8c |
| 2.7 | AssetStream (request_mesh adapter + LRU cache) | 0+14 | f880676 |
| 2.8 | StreamingBudget + Job/AssetStream wiring | 0+15 | 9c16f92 |
| 2.9 | ChangeBroadcast (sync/async/job dispatch) | 0+16 | 3d8f3d3 |
| 2.10 | ContentAddress (Python primary + GDScript wrapper) | 19+10 | d9dadc2 |
| 2.11 | world_contract preflight (allowlist + doc_health + lint) | 16+0 | 1408e6c |
| 2.12 | Plugin autoloads + setup.py CLI | 7+0 | cb46ffc |

**Final tally**: 96 pytest + 125 gut + 3 real-GPU = 224 tests. All
pass via `verify --full` in 4.6s on dev hardware.

## What changed vs the plan

Several deviations from `docs/roadmap/phase_2_foundations.md`:

1. **Junction over symlink (SA-M2.11 confirmed in practice)**: Phase 0
   already established this; Phase 2.12's setup.py CLI codified it
   as the Windows default. `mklink /D` requires admin / Developer
   Mode; junction needs neither.

2. **GDScript builtin shadowing (pitfall meta-1)**: hit twice —
   QualityTiers `get` → `get_tier`, QualityTiers `load` → `load_config`.
   Documented in pitfalls_meta.md. Pattern for future cross-impl
   classes: avoid static `get`/`load`/`set`/`free`/`call` names.

3. **--headless disables RenderingDevice (pitfall meta-2)**: user-
   prompted investigation mid-Phase 2.6 produced a real GPU test
   layer via `--display-driver windows --rendering-driver vulkan`.
   3 real RenderingDevice tests (incl. live compute shader dispatch)
   now run in `verify --full`. Spec 06 + workflows/godot_rendering_modes.md
   document the recipe.

4. **GDScript Variant type inference (Phase 2.10)**: `var val := d[k]`
   fails to infer when dict has mixed values; must annotate
   `var val: Variant = d[k]`. Similar to pitfall meta-1 in spirit;
   not yet promoted to its own pitfall entry (one hit so far).

5. **USAGE.md + 2 workflow recipes** landed mid-phase per user
   request. Front door for "how to run / test / build" — separates
   user-facing recipes from spec contracts.

6. **Lint dogfooding worked**: Phase 2.11's logging_lint caught 4
   real violations in our own Tier 0 code (direct push_error in
   AssetStream/Job/JobScheduler). Fixed during build. Validates the
   lint isn't just theoretical.

## Lessons learned

- **Cross-impl parity tests are cheap to write + high value**: the
  pattern (Python pytest + GDScript gut + shared canonical JSON
  config) caught the GDScript builtin-shadowing issues immediately
  vs hours later. Reusable template now in QualityTiers,
  SpatialIndex, ContentAddress.
- **Lazy autoload lookup for cross-system wiring**: JobScheduler +
  AssetStream publish to StreamingBudget. Both use
  `get_node_or_null("/root/StreamingBudget")` which gracefully
  no-ops in test contexts (no autoload tree) but works when the
  plugin's autoloads are live. Tests of integration still need
  manual sibling instantiation; documented in inline comments.
- **Real-GPU testing is fast** (3 tests in 2s including Vulkan
  window flash). No reason to skip it just because it's not
  --headless. Now in `verify --full` by default.
- **Phase 2.11's logger lint dogfood was a meaningful win**: had I
  not built the lint, the 4 violations would have stayed in Tier 0
  code, and every Tier 1+ author would have copied the pattern.
  The lint pays for itself on the first commit it gates.

## Open follow-ups

- [ ] Variant-inference pitfall: if pattern hits again, promote to
      pitfall meta-3. One hit isn't enough yet.
- [ ] First plan doc (Phase 3 renderer research) — start of the
      spec → plan lifecycle per spec 02. Plan doc shape needs to
      get written somewhere (probably in CONTRIBUTING.md update).
- [ ] Phase 3 (renderer research sprint) — the gate before Phase 4
      terrain MVP. ETA: 3-5 sessions per spec 15.
- [ ] Status sweep: 47 specs are still `draft`. Phase 0 close listed
      this as a "post-2-prep" task; should happen before Phase 3.
- [ ] AssetStream test for actual mesh adapter (test_mesh_adapter_*
      currently tests the failure path; should add a real GLB
      fixture once we have one).
- [ ] StreamingBudget integration test: spawn JobScheduler + Asset
      Stream + StreamingBudget as siblings, verify active_jobs +
      asset_cache_mb actually flow through. Currently each side is
      unit-tested separately; the wire is tested only indirectly.
- [ ] Capture-based renderer test layer (verify --full's 5th layer)
      stays stubbed until Phase 4 terrain MVP ships scenes worth
      capturing.

## Verification

End-to-end via `verify --full`:
- ✅ pytest: 96 cases pass in 0.92s
- ✅ gut headless: 125 cases pass in 1.3s
- ✅ gut real GPU: 3 cases pass in 2.0s (includes live compute
      shader dispatch + readback)
- ✅ preflight: 0 errors / 0 warnings (real W5 repo passes its own
      contract)
- ⏳ capture: skipped (Phase 4 land)

All 8 Tier 0 autoloads register cleanly when demo project opens.

## Refs

- Spec 06 TEST_INFRASTRUCTURE (4-tier verify CLI)
- Spec 07 JOB_SYSTEM + Spec 08a GPU_CPU_CONTRACT (Job + GpuJob)
- Spec 08 SPATIAL_INDEX (cross-impl parity)
- Spec 09 ASYNC_ASSET_STREAMING (AssetStream + mesh adapter)
- Spec 10 STREAMING_BUDGET (publish/headroom/over-budget)
- Spec 11 CHANGE_BROADCAST (sync/async/job dispatch — SA-S10)
- Spec 12 CONTENT_ADDRESSING (FileInput sentinel — SA-C2.3 + GC cap
  — SA-S2.4)
- Spec 13 QUALITY_TIERS (5-tier config + per-workload cell sizes)
- Spec 14 WORLD_CONTRACT (preflight host + modular checks)
- Spec 16 LOGGING_AND_ERROR_CONVENTIONS (Log.gd + lint)
- Spec 17 VERSIONING_AND_MIGRATION (World5.VERSION + semver helpers)
- Spec 18 PLUGIN_INSTALL_AND_DEV_LOOP (setup.py + Junction fallback)
- Pitfall meta-1 (builtin shadowing) + meta-2 (--headless / RD)
- All audit C/S/M fixes that landed inline (C2.3 FileInput, S2.4
  GC cap, S6 active_jobs publisher, S10 dispatch modes, C3.17
  placement_exclusion schema, S14 verify tier split, M11
  logging_lint integration, etc.)

Phase 2 closes. Ready for Phase 3 (renderer research sprint).
