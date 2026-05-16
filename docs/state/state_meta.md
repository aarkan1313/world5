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
| 06 | TEST_INFRASTRUCTURE | draft | none | `verify` CLI with `--fastest`/`--fast`/default/`--full` tiers; not built (Phase 2) |

## Tier 0 cross-cutting (07-18 + 08a + X_FRAME_BUDGET)

| # | Spec | Status | Code | Notes |
|---|---|---|---|---|
| 07 | JOB_SYSTEM | draft | none | Wraps WorkerThreadPool; publishes `active_jobs` to streaming budget |
| 08 | SPATIAL_INDEX | draft | none | Grid backing; Python + GDScript parity; per-workload cell sizes (spec 13) |
| 08a | GPU_CPU_CONTRACT | draft | none | Post-audit; 5 rules + `GpuJob` + `GpuResourceTracker` |
| 09 | ASYNC_ASSET_STREAMING | draft | none | Wraps `ResourceLoader.load_threaded_*`; publishes to `asset_cache_mb` budget |
| 10 | STREAMING_BUDGET | draft | none | Shared accountant; per-tier ceilings from spec 13 |
| 11 | CHANGE_BROADCAST | draft | none | Pub/sub with sync/async/job dispatch; metadata schemas defined post-self-audit |
| 12 | CONTENT_ADDRESSING | draft | none | `FileInput` sentinel for file inputs (post-self-audit); 20 GB GC cap default |
| 13 | QUALITY_TIERS | draft | none | 5 tiers (low/medium/high/ultra/cinematic; `cinematic` renamed from `ultra_far`) |
| 14 | WORLD_CONTRACT | draft | none | Modular per-system preflight; validates world bundles |
| 15 | RENDERER_RESEARCH_BRIEF | draft | n/a | Brief, not a system; output is spec 15a decision doc |
| 16 | LOGGING_AND_ERROR_CONVENTIONS | draft | none | 5 levels; structured + JSON; lint enforced |
| 17 | VERSIONING_AND_MIGRATION | draft | none | Semver; migration scripts for MAJOR/breaking-MINOR; no retro-edits |
| 18 | PLUGIN_INSTALL_AND_DEV_LOOP | draft | none | 3 install methods; mklink prereq documented |
| X | FRAME_BUDGET | draft | none | Post-audit; engine reserves 8 ms of 16.6 ms at high tier; per-system table sums exactly to 8.0 |

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
