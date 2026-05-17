"""W5 texture pipeline — promotion, manifest builders, batch drivers.

Per spec 25 + plan 25 (Phase 5). Owns the dev-side texture pipeline
that turns the FLUX/StableMaterials diffusion stack's raw candidates
into world-bundle-ready PBR sets.

Phase 5.5 ships `promote.py` first (workflow-critical net-new tool;
not present in W4). Phase 5.1 ports the W4 `tx_*.py` modules
(diversity batch + QA stack) when the parallel W4 cleanup chat lands.

Modules:
  - promote: Copy candidate textures into world bundle + update
    material_variants.json + run preflight.
  - (5.1 deferred): tx_pipeline, tx_seamless, tx_variant_select,
    tx_pbr_hybrid, tx_pbr_derive, tx_pbr_sm, tx_seam_repair, tx_qa,
    tx_family, tx_macro_terrain, tx_subject — ported from W4.
"""
