# Phase 2 — Foundation Build (Tier 0 Primitives)

> Phase: Phase 2 (foundation; everything depends on this)
> Status: 🚧 in progress
> Estimated sessions: 8-15
> Owner: agent + user joint
>
> Goal: build the Tier 0 cross-cutting primitives in code. Every Tier
> 1+ vertical system depends on these. Build with test coverage from
> day 1 so every later system has a working `verify` to lean on.

## Scope (what's in)

Per spec 01 module layout + 13 Tier 0 specs:

### Test infrastructure first (spec 06)
- gut installed at `engine/addons/gut/` (NB: gut is third-party Godot
  addon; allowed by spec 04 allowlist)
- pytest harness at `tests/` + `pipeline/*/tests/` working
- `python -m world5.verify` CLI with 4 tiers (`--fastest` / `--fast` /
  default / `--full`)
- Capture-based test framework (motion/spin/startup profilers)
  scaffolded but not full — first scene tests land with terrain MVP

### Tier 0 systems in dependency order
1. **Log** (spec 16) — every other Tier 0 uses it
2. **World5** (spec 17 — version singleton + helpers)
3. **QualityTiers** (spec 13) — config schema + Python + GDScript
   resolvers + cross-impl parity test
4. **Job** + **JobScheduler** (spec 07)
5. **GpuJob** + **GpuResourceTracker** (spec 08a)
6. **SpatialIndex** (spec 08) — Python + GDScript + cross-impl test
7. **AssetStream** (spec 09)
8. **StreamingBudget** (spec 10) — Job system publishes `active_jobs`
9. **ChangeBroadcast** (spec 11) — with sync/async/job dispatch +
   metadata schemas
10. **ContentAddress** (spec 12) — Python primary; GDScript read-only
    wrapper; `FileInput` sentinel for file-hashing
11. **WorldContract** (spec 14) — modular preflight host

### Preflight scripts (spec 04 + 05 + 16)
- `pipeline/world_contract/godot_root_check.py` (spec 04 allowlist)
- `pipeline/docs/doc_health.py` (spec 05 line caps + index
  consistency + SITEMAP regen + diff)
- `pipeline/world_contract/logging_lint.py` (spec 16 — no direct
  print/push_* outside Log.gd)

### Plugin wiring
- `engine/plugin.gd` registers autoloads (currently stubbed)
- `setup.py` script (per spec 18) for cross-platform addon link

## Scope (what's NOT in — defer to later phases)

- ❌ Any vertical system (terrain, materials, decoration, etc.)
- ❌ Renderer research sprint (Phase 3)
- ❌ Spec 15a renderer decision doc
- ❌ Specific tier numbers in `quality_tiers.json` (placeholders only;
  calibration sprint at Phase 4.5)
- ❌ Migration script infrastructure beyond spec 17 contract (no
  migrations to ship yet)
- ❌ Plugin packaging release build (Phase 16)

## Pre-flight (before starting)

- [ ] Spec status sweep: promote audited specs `draft → reviewed`
      (all 47 specs were audit-passed; tag them collectively in one
      commit before Phase 2 work starts; future spec changes go
      `draft` again until next review)
- [ ] Confirm `pip install -e ./pipeline` works on dev machine
- [ ] Confirm `demo/project.godot` opens in Godot 4.5+ without errors
- [ ] Decide GodotEditor + Python version pins for `pyproject.toml`
      `requires-python = ">=3.12"` already; pin Godot version in
      `engine/plugin.cfg` if needed (currently no pin)

## Build order rationale

**Why test infra first**: every other Tier 0 needs tests from day 1
(spec 06 requirement). Without `verify` running, we can't gate any
later commit.

**Why Log + World5 second**: every other system calls `Log.info()` etc.
Building them first means no class needs to be revised later when
Log lands.

**Why QualityTiers third**: every other system reads per-tier knobs
(JobScheduler reads `active_jobs` cap, AssetStream reads
`asset_cache_mb`, etc.). Built before consumers exist.

**Why ContentAddress + WorldContract last**: they're consumers of all
the others (they validate / persist what other systems produce).

**Why cross-impl parity tests inline**: SpatialIndex + QualityTiers +
Kernels all need Python ↔ GDScript outputs to match exactly. Build
the parity-test harness alongside the first cross-impl system; reuse
for the next.

## Per-system sub-checklists

Each Tier 0 system gets a brief sub-checklist below. Granular per-system
plans (`docs/plans/`) get written when the system is actively being
built — for Tier 0 we keep the plan inline here since each system is
small (per spec 02 R5: trivial systems can have inline plans).

### Phase 2.1 — Test infrastructure (spec 06)
- [ ] Install gut as Godot addon at `engine/addons/gut/`
- [ ] First gut test at `engine/tests/unit/test_smoke.gd` (asserts
      `true == true`) to validate harness
- [ ] First pytest at `tests/unit/test_smoke.py` (asserts `True`) to
      validate pytest harness
- [ ] `pipeline/world5/verify/__init__.py` — `run_verify(mode)` skeleton
- [ ] `python -m world5.verify --fastest` works (pytest only, ~15s)
- [ ] `python -m world5.verify --fast` works (pytest + gut, ~90s)
- [ ] `python -m world5.verify` default mode works (+ preflight; ~3 min)
- [ ] `python -m world5.verify --full` works (+ capture diff; ~15 min;
      capture diff is stub until first capture scene exists)
- [ ] CI / pre-commit hook integration (defer if user prefers)

### Phase 2.2 — Log + World5 (spec 16 + 17)
- [ ] `engine/scripts/core/Log.gd`: 5 levels, structured + JSON output,
      per-system verbose, `set_format` / `set_output` / `set_level`
- [ ] `pipeline/world5/log.py`: mirror API (info/warn/error/fatal),
      JSON mode
- [ ] `engine/scripts/core/World5.gd`: VERSION constant from
      plugin.cfg, `parse`, `is_compatible`, `needs_migration`,
      `migration_path`
- [ ] `pipeline/world5/version.py`: same shape, parses plugin.cfg
- [ ] gut tests for Log (assert formatted lines match shape; assert
      JSON mode emits valid JSON)
- [ ] pytest for log.py + version.py (cross-impl parity test for
      log formats)

### Phase 2.3 — QualityTiers (spec 13)
- [ ] `engine/resources/quality_tiers.json` — placeholder per-tier
      values from spec 13 example
- [ ] `engine/resources/quality_tiers.schema.json` — JSON Schema
- [ ] `engine/scripts/core/QualityTiers.gd`: load, get, get_current,
      names
- [ ] `pipeline/world5/quality_tiers.py`: mirror API
- [ ] `tests/test_quality_tiers_cross_impl.py` — Python ↔ GDScript
      parity (gold-standard pattern for cross-impl tests)
- [ ] gut + pytest unit tests for resolvers

### Phase 2.4 — Job system (spec 07)
- [ ] `engine/scripts/core/Job.gd` — base class, Priority enum, Status
      enum
- [ ] `engine/scripts/core/JobScheduler.gd` — submit, get_status,
      await_completion, cancel, is_shutting_down, get_queue_depth,
      get_running_count, debounced publish to StreamingBudget
      `active_jobs`
- [ ] gut tests: priority order, dependency edges, cancellation,
      shutdown drain (`_exit_tree` doesn't leak workers)
- [ ] `engine/examples/job_example_chunk_bringup.gd` — multi-job
      dependency chain demo

### Phase 2.5 — GpuJob + GpuResourceTracker (spec 08a)
- [ ] `engine/scripts/core/GpuJob.gd` — extends Job; routed via
      `RenderingServer.call_on_render_thread`
- [ ] `engine/scripts/core/GpuResourceTracker.gd` — register /
      unregister / get_allocations / _exit_tree safety net
- [ ] Lint script (Python): `pipeline/world_contract/gpu_lint.py` —
      walks `engine/scripts/` for `RenderingDevice.` calls inside
      `Job._execute()` overrides; CI fails if violated
- [ ] gut tests: GpuJob dispatch latency, GpuResourceTracker
      registration counts
- [ ] `engine/examples/gpu_job_example.gd`

### Phase 2.6 — SpatialIndex (spec 08)
- [ ] `engine/scripts/core/SpatialIndex.gd` — uniform grid backing;
      insert/remove/update/query_radius/query_rect/query_nearest;
      reads per-workload cell_size_m from QualityTiers
- [ ] `pipeline/world5/spatial_index.py` — mirror API
- [ ] `tests/test_spatial_index_cross_impl.py` — Python ↔ GDScript
      parity
- [ ] gut + pytest unit tests
- [ ] Performance test: 10k items + query_radius < 1ms Python, < 5ms
      GDScript

### Phase 2.7 — AssetStream (spec 09)
- [ ] `engine/scripts/core/AssetStream.gd` — singleton autoload;
      request, get_status, get_resource, await_ready, cancel, evict,
      cache budget integration with StreamingBudget
- [ ] `request_mesh()` adapter: GLB → ArrayMesh extraction
- [ ] gut tests: request lifecycle, cache hit/miss, LRU eviction,
      mesh adapter

### Phase 2.8 — StreamingBudget (spec 10)
- [ ] `engine/scripts/core/StreamingBudget.gd` — autoload; publish /
      clear / get_total_usage / get_budget / get_headroom /
      is_over_budget / get_top_publishers / get_history
- [ ] gut tests: publish dedup, budget calculation, history ring
- [ ] Integration test: JobScheduler publishes `active_jobs`;
      AssetStream publishes `asset_cache_mb`; assert budget reflects

### Phase 2.9 — ChangeBroadcast (spec 11)
- [ ] `engine/scripts/core/ChangeBroadcast.gd` — autoload; publish,
      subscribe (with sync/async/job dispatch + region filter +
      sources filter), unsubscribe, get_recent
- [ ] Metadata schemas per source name (placement_exclusion,
      terrain_deformation, path_zone, decoration_zone — schema only;
      no producers yet)
- [ ] gut tests: filter correctness, three dispatch modes work,
      coalescing within frame

### Phase 2.10 — ContentAddress (spec 12)
- [ ] `pipeline/world5/content_address.py` — ContentAddressStore class;
      hash_inputs, hash_file_input (FileInput sentinel), has/get/put,
      declare_dependency, find_dependents, invalidate,
      evict_unreferenced, gc_if_over_cap (default 20 GB)
- [ ] `engine/scripts/core/ContentAddress.gd` — read-only wrapper
- [ ] pytest tests: hash determinism, FileInput content-hashing,
      dependency graph invalidation, GC cap behavior
- [ ] `python -m world5.content_address verify` CLI for store
      integrity

### Phase 2.11 — WorldContract preflight + lint scripts
- [ ] `pipeline/world_contract/__init__.py` — `validate(world_path,
      tier, strict)` + ContractResult shape
- [ ] `pipeline/world_contract/godot_root_check.py` per spec 04
- [ ] `pipeline/world_contract/logging_lint.py` per spec 16 + audit
      M11
- [ ] `pipeline/docs/doc_health.py` per spec 05 + SA-MX3 — line caps,
      orphan link check, SITEMAP regen + diff
- [ ] Per-system contract check registration pattern (decorator-based
      from spec 14 open question; or manual at this stage)
- [ ] `python -m world5.world_contract --world <path>` CLI
- [ ] pytest coverage of every check

### Phase 2.12 — Plugin wiring + setup.py
- [ ] Uncomment autoload registrations in `engine/plugin.gd`
- [ ] `pipeline/world5/setup/__init__.py` + CLI:
      `python -m world5.setup install_demo` (creates symlink /
      junction at `demo/addons/world5`)
- [ ] `python -m world5.setup verify_install <path>` per spec 18 +
      spec 43
- [ ] Sanity check: open `demo/project.godot`, plugin enables,
      autoloads loaded, no errors

## Commit cadence

Each numbered sub-phase (2.1 through 2.12) gets its own commit. Format:

```
feat(<system>): <one-line summary>

What shipped:
- <bullet list>

What's tested:
- <bullet list>

Refs: spec NN_NAME, Phase 2 checklist 2.X

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

After all 12 sub-phases land, the Phase 2 close commit lands per
spec 02 lifecycle (build-note + STATE + ROADMAP update + push).

## Verification per sub-phase

Each sub-phase must:
- ✅ All new code has tests (gut + pytest as appropriate)
- ✅ `python -m world5.verify` default mode passes
- ✅ No `print` / `push_warning` / `push_error` outside `Log.gd`
- ✅ Spec compliance verified (`Quality bar` section items met)

## Phase 2 close criteria

Phase 2 is "done" when:
- [ ] All 13 Tier 0 systems live in code + tested
- [ ] `verify --full` runs end-to-end (capture diff stubs OK; real
      captures land at Phase 4)
- [ ] `demo/project.godot` opens + plugin enables + autoloads
      register + no errors
- [ ] `pip install -e ./pipeline` + `python -m world5.verify --fastest`
      works in < 15s
- [ ] All Tier 0 specs promoted from `reviewed` → `shipped`
- [ ] Phase 2 build-note in `docs/build-notes/`
- [ ] STATE.md + ROADMAP.md + state/state_meta.md updated
- [ ] Push to origin/main

## Open questions / decisions to lock during Phase 2

- [ ] gut version pin: latest stable from github.com/bitwes/Gut, or
      pin to a specific release? (Probably latest stable + lock in
      requirements; defer)
- [ ] `python -m world5.verify` exit codes: spec 06 defines 0/1/2/3;
      confirm at build time
- [ ] Logging output destination defaults: dev = stdout, shipping =
      stdout; configurable. Lock default
- [ ] Content addressing store path: `pipeline/.content_addressed_store/`
      (gitignored). Confirm path

## Doc cap status

This file: ~200 lines (under 300 cap; per-system sub-checklists keep
it scannable).
