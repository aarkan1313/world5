# State: Meta + Tier 0 Cross-Cutting Systems

> Per-system state for meta specs (00-06) + Tier 0 cross-cutting
> primitives (07-18 + 08a + X_FRAME_BUDGET). Updated when systems ship.
>
> Cap: ≤ 300 lines (spec 05).
> Last updated: 2026-05-16.

## Meta specs (00-06)

| # | Spec | Status | Code | Notes |
|---|---|---|---|---|
| 00 | SPEC_TEMPLATE | draft | n/a | Template for all specs; updated post-self-audit with tier vocab + cross-spec contract reminders |
| 01 | MODULE_LAYOUT | draft | **scaffold shipped (Phase 0)** | Directory tree + plugin.cfg + project.godot + pyproject.toml all live at commit `f73b4f8` |
| 02 | CONTRIBUTING_LIFECYCLE | draft | none (process realized) | Spec → plan → build-note → state cycle; first build-note shipped in Phase 0 close |
| 03 | PILLARS | draft | n/a | Quality > Performance > Architecture > Time |
| 04 | GODOT_ROOT_ALLOWLIST | draft | none | Preflight `godot_root_check.py` not built yet (Phase 2). Allowlist enforced manually during Phase 0 |
| 05 | DOC_ARCHITECTURE | draft | **realized in Phase 0** | Top-level + per-tier docs scaffold per spec 05 shipped at `f73b4f8` |
| 06 | TEST_INFRASTRUCTURE | draft | **shipped (Phase 2.1)** | `verify` CLI with all 4 tiers active; pytest + gut + real-GPU + preflight + capture layers. 224 tests pass <5s |

## Tier 0 cross-cutting (07-18 + 08a + X_FRAME_BUDGET)

| # | Spec | Status | Code | Notes |
|---|---|---|---|---|
| 07 | JOB_SYSTEM | draft | **shipped (Phase 2.4)** | Job + JobScheduler autoload; priority queue + deps + await + cancel + shutdown drain; publishes `active_jobs` |
| 08 | SPATIAL_INDEX | draft | **shipped (Phase 2.6)** | Python + GDScript; uniform grid; query_radius/rect/nearest k-NN; cross-impl parity tested |
| 08a | GPU_CPU_CONTRACT | draft | **shipped (Phase 2.5)** | GpuJob extends Job; routed via `RenderingServer.call_on_render_thread`. GpuResourceTracker autoload |
| 09 | ASYNC_ASSET_STREAMING | draft | **shipped (Phase 2.7)** | AssetStream autoload; request/await/cache/LRU; request_mesh adapter for GLB→Mesh extraction |
| 10 | STREAMING_BUDGET | draft | **shipped (Phase 2.8)** | StreamingBudget autoload; per-tier ceilings; get_top_publishers; Job + AssetStream wired |
| 11 | CHANGE_BROADCAST | draft | **shipped (Phase 2.9)** | sync/async/job dispatch; metadata schemas verified via placement_exclusion test |
| 12 | CONTENT_ADDRESSING | draft | **shipped (Phase 2.10)** | Python ContentAddressStore (FileInput sentinel + 20 GB GC cap); GDScript wrapper for stamp reading |
| 13 | QUALITY_TIERS | draft | **shipped (Phase 2.3)** | 5 tiers config + Python + GDScript resolvers + cross-impl parity test; `get_tier`/`load_config` (builtin shadowing avoided) |
| 14 | WORLD_CONTRACT | draft | **shipped (Phase 2.11)** | Preflight host + 3 cross-cutting checks (allowlist, doc_health, logging_lint); real W5 repo passes its own contract |
| 15 | RENDERER_RESEARCH_BRIEF | draft | n/a | Brief, not a system; output is spec 15a decision doc (Phase 3 next) |
| 16 | LOGGING_AND_ERROR_CONVENTIONS | draft | **shipped (Phase 2.2)** | Log.gd + Python mirror; 5 levels; structured + JSON; lint enforced |
| 17 | VERSIONING_AND_MIGRATION | draft | **shipped (Phase 2.2)** | World5.gd VERSION + parse/is_compatible/migration_path; Python mirror reads plugin.cfg |
| 18 | PLUGIN_INSTALL_AND_DEV_LOOP | draft | **shipped (Phase 2.12)** | plugin.gd autoloads + setup.py CLI (install_demo, verify_install); Junction fallback |
| X | FRAME_BUDGET | draft | n/a | Spec only — frame allocations consumed by render-touching systems (Phase 4+) |

## What's load-bearing in this tier

These are the cross-cutting primitives every Tier 1+ system depends on.
Build order (per ROADMAP Phase 2):
1. Test infrastructure (so everything else has tests)
2. Logging + Job system + Spatial index + Async asset streaming
3. Streaming budget + Change broadcast + Content addressing
4. GPU/CPU contract (08a) + Frame budget enforcement
5. Doc architecture + Godot root allowlist preflight

## Known open questions

- **Spec status sweep**: all specs say `draft`; do we batch-promote
  the audited set to `reviewed` at Phase 0 close? See ROADMAP Phase 0
  checklist.
- **Calibration sprint** (Phase 4.5): when do per-tier numbers in
  spec 10 + spec 13 + X_FRAME_BUDGET get re-measured on real RTX 3060
  hardware? After terrain MVP.

## Carry-over from W4.1 (per-system review)

Each Tier 0 primitive's W4.1 reference is in its spec's References
section. None of W4.1's code carries over directly — W5 builds fresh
on the contract, with W4.1 patterns as design reference only.

Exceptions where W4.1 code may copy:
- Spec 13 quality tiers: W4.1 `pipeline/quality_tiers.py` is a clean
  small module; review for direct copy at Phase 2.
- Spec 10 streaming budget: W4.1 `StreamingBudgetAccountant.gd` is
  small and proven; review for direct copy.

All carry-over decisions happen at spec-promotion time, not now.

## Doc cap status

- This file: ~60 lines (well under 300 cap)
- Plenty of room as systems ship + each gets a 2-3 line state update
