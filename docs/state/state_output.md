# State: Tier 3 Output / Packaging Systems

> Per-system state for Tier 3 specs (42-44). Updated when systems ship.
>
> Cap: ≤ 300 lines (spec 05).
> Last updated: 2026-05-16.

## Tier 3 systems (42-44)

| # | Spec | Status | Code | Notes |
|---|---|---|---|---|
| 42 | BAKE_RECIPES | draft (skeleton) | none | v1 ships contract + runner skeleton + one example (`debug_overhead`). 2.5D / topdown / world-map recipes deferred. Cold-start ≤ 10s, warm ≤ 2s (post-self-audit SA-S5.5) |
| 43 | PLUGIN_PACKAGING | draft | none | Reproducible release build + CHANGELOG discipline. Pipeline ships pyproject.toml; `pip install -e ./pipeline` (PyPI deferred). Consumer install-from-artifact steps documented |
| 44 | FORKABILITY_VALIDATION | draft | none | 3 fork projects: bare / customized / pipeline-only. `validate --fork-path` mechanically runs world contract + verify_install + verify --fast on the fork. Forks live at `D:/tmp/w5_forks/` during validation |

## What's load-bearing in this tier

Phase 15-16 work. These specs are the "is W5 actually shippable to a
consumer" test:
- **Phase 15 — Bake recipes**: Per-recipe sprints (2.5D first, then
  topdown, then world-map) as consumers demand them
- **Phase 16 — Forkability validation**: The structural test of "done"
  per success metric. 3 forks must pass.

## Cross-spec contracts

- **Bake recipes (42) ↔ Terrain renderer (21) + Atmosphere (30) +
  Lighting (31)**: recipes load worlds via the same runtime path;
  any post-process / camera override is recipe-specific
- **Packaging (43) ↔ Versioning (17) + Install (18) + Test infra (06)**:
  release build runs `verify --full` as gate; bumps version per spec
  17 rules; produces artifact consumed via spec 18 install methods
- **Forkability (44) ↔ Every spec**: each fork validates the whole
  engine; surfaces gaps in any system

## Known open questions

- **Recipe order**: probably 2.5D first (consumer game's likely first
  need), then topdown (in-game map), then world-map (strategic view).
  Per ROADMAP Phase 15
- **Fork D (wizard game itself)**: probably becomes Fork D when the
  wizard game exists. Not part of v1 validation but is the existence
  proof for success metric

## What "done" looks like

Per the W5 success metric:
- 3 fork projects (bare 3D walk / customized 3D walk / pipeline-only)
  all pass forkability validation
- Bundled `demo/` project showcases the 2-biome target
- 2.5D / topdown / world-map bake recipes shipped (or one of them; the
  bake recipe contract is what matters, not all 3 recipes)
- W5 v0.1.0 tagged + CHANGELOG entries exist for every release
  artifact

This is Phase 16/17 work; ~6 months out at realistic cadence.

## Doc cap status

- This file: ~50 lines (well under 300 cap)
