# W5 Re-Audit Findings — Phases 0-5

> Date: 2026-05-17
> Charter: [AUDIT_PHASE_0_5_2026_05_17.md](AUDIT_PHASE_0_5_2026_05_17.md)
> Method: 4 read-only parallel audit subagents — (a) Phases 0+2, (b)
> Phase 3+4, (c) Phase 5, (d) ROADMAP/STATE cross-check vs spec audits
> Trigger: Walking demo Phase 5.4 alpine ships with visible bugs
> (chunk seams + dead mid/rock textures + tile repeat at eye height)
> that violate specs 21 + 23 + 24. User direction: "we will just need
> to fix everything we should have at this point, reaudit the whole
> project as needed."

## Bottom line

**Phases 4, 4.5, 4.6, 5.4, 5.5 all claim ✅ done while shipping
unfinished core systems**. The build notes are mostly honest about
deferred work; ROADMAP + STATE glossed over the cuts. Three
critical user-visible bugs ship today because the renderer's
contract with specs 21 + 23 was never met.

**No phase 0 or phase 2 critical blockers found** — Tier 0
foundations are solid.

**The fix is sub-phase 4.9 + spec sweep + roadmap correction.** Not
rebuilding from scratch.

## Critical findings (user-visible; must fix before Phase 5 close)

### C1 — Outer clipmap rings sample one heightmap page → visible chunk seams

- **Spec violation**: spec 21 implicitly requires "no seam" via
  "60fps zero hitches + full detail"
- **Root cause**: `engine/scripts/terrain/TerrainWorld.gd:444-452`
  binds one page per ring (covers `snapped_center` only). Walking
  demo defaults: ring 0 = 127.5 m fits one 256 m page; rings 2-4
  are 510 m / 1020 m / 2040 m wide but only get one 256 m page
  bound → texture stretches to fill the rest
- **Visible as**: seam lines where one stretched ring's edge meets
  the next stretched ring's edge
- **Effort**: 1 session
- **Fix sketch**: ResidencyManager already computes multi-page
  required-set per ring. Either (a) bind heightmap as Texture2DArray
  per ring with per-fragment world-XZ → layer selection, (b) merge
  adjacent pages into one wider texture at bind time, or (c) world-
  spanning heightmap texture with sparse residency. (a) is cheapest;
  matches existing array binding patterns from Phase 5.5

### C2 — Per-fragment slot selection not implemented → mid + rock textures are dead weight

- **Spec violation**: spec 23 §"Surface slot model" + spec 22
  §"surface_slots" declare per-slot selectors (`slope_deg`,
  `elevation`, `noise`) that should drive per-fragment slot weight.
  Spec 23: "Surface slot world mask bakes these into a shared
  Texture2DArrayRD sampled at world XZ"
- **Root cause**: `engine/scripts/terrain/material/SurfaceSlotMask.gd`
  only loads JSON metadata; **zero shader code does selection**;
  `TerrainWorld.gd:322` binds only `mv.slots[0]` (the first slot).
  Texture team's promoted mid (lichen_moss) + rock (granite_lichen)
  bundles are on disk but never reach GPU
- **Effort**: 2-3 sessions
- **Fix sketch**: extend shader with a per-fragment slot-weight
  computation from `slope_deg` (derived from heightmap derivatives)
  + `elevation`; bind ALL slot windows (start/count per slot, not
  just first); fragment computes weighted blend across active slots

### C3 — Sibling 3-tap noise frequency too low → visible texture repeat at standing eye height [✅ closed 2026-05-17 Phase 5.4.b.2]

- **Spec violation**: spec 24 Quality bar "no obvious texture repeats"
- **Root cause**: `engine/shaders/terrain_clipmap.gdshader`
  `sibling_blend_freq = 0.10` → 10 m wavelength on 4 m tiles. At
  standing eye height looking 5-30 m ahead, same 4 m tile read
  2-3 times in a row before the noise switched sibling
- **Fixed by**: Phase 5.4.b.2 added `terrain_sibling_blend_freq`
  per tier in `quality_tiers.json` (low 0.20, medium 0.25, high
  0.30, ultra 0.35, cinematic 0.40). New `MaterialPipeline.bind_sibling_blend_freq`
  binder + `TerrainWorld._bind_slots_with_catalog` wire-up via
  `QualityTiers.get_current()`. +2 TDD tests. High tier now ships
  3× finer noise wavelength = sibling switch every ~3 m vs old
  ~10 m. Build note `phase_5_4_b_partial_2026_05_17.md`

### C4 — Spec 19 kernel system half-built; ErosionKernel + DemFeatureKernel + KernelComposer missing

- **Spec violation**: spec 19 §"Kernel types shipped in v1" lists 3
  kernels + KernelComposer; only NoiseStackKernel shipped
- **Downstream impact**: Phase 10 water consumes ErosionKernel's
  `drainage_map` + `flow_direction` + `flow_accumulation` outputs
  (spec 35). Water is blocked until erosion ships
- **Effort**: multi-sprint (ErosionKernel alone 4+ sessions per
  spec 19 §"World-size bound"; DemFeatureKernel 4+ sessions per
  Sprint 3; KernelComposer 2-3 sessions)
- **Fix sketch**: phase 5.7 erosion sprint per ROADMAP §"Cross-phase
  kernel deliveries" (which already flagged this!). Plan doc first,
  then build

## Significant findings (correctness / acknowledgment)

### S1 — RTX 3060 perf claim is inverted

- **What ROADMAP says**: Phase 4.5 calibration "F2 engaged
  conservatively for 3060"
- **What's true**: 5090 measurements are 4-6 ms at 4-6 rings (over
  the 2.0 ms budget). Extrapolating to 3060 (~3-4× slower for
  geometry-bound work) gives **13-17 ms at 4 rings → 7-12× over
  budget**. F2 fallback decision is TBD pending real hardware
- **Effort**: 1-2 sessions (need RTX 3060 access or shader profiling
  on lower-clock simulation)
- **Fix**: amend ROADMAP + spec 21 perf bar to reflect the real
  extrapolation honestly; flag 3060 viability as open question

### S2 — Walking demo macro_albedo missing → far-field uses fallback_color [✅ closed 2026-05-17 Phase 4.9.c]

- **Spec violation**: spec 23 line 43-47 "REQUIRED for any world
  configured with visibility_ship_distance_m > 2km"
- **Root cause**: `engine/worlds/walking_demo/` had no
  `macro_albedo.png` or `.json` at the world root. Logs warned
  "bundle missing macro_albedo.json" on every load
- **Fixed by**: Phase 4.9.c ran `tx_macro_terrain
  --purpose-candidates --promote-purpose` after porting the script
  in Phase 5.1 + bumping it to read W5 `material_kit` (in addition
  to W4 `kit_dir`). Wrote `engine/worlds/walking_demo/macro_albedo.json`
  (world-root manifest, AABB ±4 km) + promoted alpine purpose-preset
  PNG. Far-field now reads as broad snowfield. Build note
  `phase_4_9_c_macro_albedo_2026_05_17.md`. Also added preflight
  `macro_albedo_*` checks (+4 tests)

### S3 — Walking demo detail/ overlays empty → spec 24 Layer 2 inactive

- **Spec violation**: spec 24 Layer 2 + spec 23 §"detail overlays"
  example layout
- **Root cause**: walking demo has `detail_array.json` (`detail_tiles:
  []`) + gitkeeped `detail/` dir but no actual overlay tiles
- **Effort**: 2-3 sessions (5-7 detail tiles per biome via
  `tx_pipeline` with detail-overlay prompts; promote via promote.py;
  detail-array binder already wired)
- **Note**: blocked on texture-team authoring (or Phase 5.1 module
  port to enable W5-side authoring)

### S4 — Phase 5.1 module port held → fresh dev cannot run pipeline end-to-end

- **Spec violation**: spec 25 §"Public API" + plan 25 step 5.1
- **Root cause**: `pipeline/world5/textures/` contains only
  `__init__.py` + `promote.py`. Plan calls for 8 tx_*.py modules
  + 5 driver CLIs (`diversity.py`, `contact_sheet.py`, `review.py`,
  `material_variants_builder.py`)
- **Effort**: 1-2 sessions (file-copy + path edit per plan; was held
  due to parallel-chat work in W4, which the texture team now seems
  to have completed at D:/tmp/)
- **Fix**: unblock 5.1 port; the texture team's external chain is
  now stable enough to snapshot

### S5 — GPU mutex (TRELLIS coordination) not implemented

- **Spec violation**: spec 25 §"GPU mutex with TRELLIS pipeline"
  documents the contract; code missing
- **Effort**: 1 session
- **Note**: only becomes critical when Phase 6 (TRELLIS) runs
  concurrent with Phase 5 (texture batches). Pre-emptive build

### S6 — QA gates (spec 25 §Quality bar) not ported to W5 pipeline

- **Spec violation**: spec 25 lists "4 gating + 2 advisory" QA
  checks; W5 pipeline lacks `tx_qa.py` (held with module port)
- **Effort**: 1-2 sessions (carry-as-is W4 port + wire into
  diversity.py batch driver)

### S7 — Per-biome YAML layout missing (`pipeline/biomes/`) [✅ closed 2026-05-17 Phase 5.4.b.1]

- **Spec violation**: spec 25 §"Per-biome YAML layout" + plan 25 step 1
- **Fixed by**: Phase 5.4.b.1 ported `pipeline/biomes/alpine.yaml`
  (51 candidates across ground/mid/rock) + `pipeline/biomes/forest.yaml`
  (21 mid-only — forest ground/rock are real-ortho not AI). Both
  parse cleanly + match `diversity.py` schema. PURPOSE_PRESETS
  extraction from `tx_macro_terrain.py` to YAML deferred — they're
  only consumed by tx_macro_terrain itself, not by diversity.py, so
  the in-code dict + YAML for diversity coexist without conflict

### S8 — Spec 23 biome_catalog.json missing from walking_demo

- **Spec violation**: spec 22 §"Catalog schema" + spec 14 world
  contract requires biome_catalog for any world that ships
- **Effort**: 0.5 session (author single-biome catalog for alpine)
- **Note**: minor for Phase 4 (single biome means catalog is mostly
  pass-through), critical for Phase 6 (second biome needs it)

## Minor findings (polish; track in PHASE_DEBT.md)

| # | Finding | Spec | Effort |
|---|---|---|---|
| M1 | `engine/addons/` dir not pre-created | 01 | < 1 sess |
| M2 | `godot_root_allowlist.json` machine-readable copy missing | 04 | < 1 sess |
| M3 | Per-tier roadmap files not created | 05 | 1-2 sess |
| M4 | `verify` mode timing targets not characterized | 06 | 2-3 sess |
| M5 | World contract not run end-to-end on walking_demo at commit-time | 14 | < 1 sess |
| M6 | `setup install_demo` CLI missing | 18 | 1-2 sess |
| M7 | `pipeline/world5/textures/README.md` missing (dev-only operator model not surfaced) | 25 | 0.5 sess |
| M8 | TerrainWorld.gd at 514 lines (>50% of 800-line cap with Phase 6 work ahead) | 21 | track only |
| M9 | Page determinism at boundaries not tested | 20 | 1-2 sess |

## Meta-finding: ROADMAP + STATE are out of sync with build notes

Build notes (the date-stamped session diaries) are honest about
deferred work. ROADMAP.md + STATE.md gloss over those cuts. Example:

- Phase 5.5 build note line 61: "Per-fragment slot selection — Phase
  5.5 ships single-active-slot (Phase 6 multi-biome will widen...)"
- STATE.md (same date) says "Layer 1+2 active" with no caveat
- ROADMAP.md says Phase 5.5 ✅ done with no caveat

This is the **systemic gap**: docs at the *aggregate* level lie by
omission while docs at the *transactional* level (build notes) tell
the truth. The fix is roadmap discipline — every phase close must
update ROADMAP + STATE to reflect what BUILD NOTES say, not what
the spec promised.

## Proposed sprint sequence (close gaps in priority order)

### Sub-phase 4.9 — Renderer correctness (3-5 sessions)

Fixes C1 + C2 + S2 + S8. The renderer's spec-21+22+23 contract is
honored end-to-end.

- 4.9.a: multi-page heightmap binding (C1) — 1 session
- 4.9.b: per-fragment slot selection (C2) — 2-3 sessions
- 4.9.c: macro_albedo authored + bound in walking_demo (S2) — 1 session
- 4.9.d: biome_catalog.json authored (S8) — 0.5 session
- 4.9 close: 4.9 build note + ROADMAP/STATE amendment + spec 21
  per-fragment slot section made explicit

### Phase 5.1 unblock — module port (1-2 sessions)

Now that texture team's external chain is stable, snapshot it. Fixes
S4 + S6 + S7. Enables fresh-dev pipeline runs.

### Phase 5.4.b — detail overlays + 5.6 calibration (3-4 sessions)

After 5.1 + 4.9 land:
- Author 5-7 detail tiles for alpine → promote → walking demo
  visually completes spec 24 Layers 1+2+3 (S3)
- Tune sibling_blend_freq per tier on real walking demo (C3)
- Calibrate per spec 21 perf bar; honest 3060 number (S1)

### Phase 5.7 — Erosion sprint (multi-sprint)

Per ROADMAP §"Cross-phase kernel deliveries" (which already noted
this needs to ship before Phase 10). Fixes C4 partially (ErosionKernel
+ KernelComposer; DemFeatureKernel deferred to dedicated sprint).
Plan doc first.

### Spec status sweep (1 session)

Promote 48 specs from `draft` → `reviewed` where current state
matches. Specs that DON'T match (e.g. spec 21's per-fragment slot
selection) get explicit amendment. ROADMAP + STATE updated.

### Then: Phase 6 (forest second biome)

Only after 4.9 + 5.1 + 5.4.b + 5.6 close. Phase 6's contract is
"biome-to-biome works"; it's testable as soon as multi-slot rendering
is real.

## What this doesn't say

- **No Phase 0/2 work needed.** Tier 0 foundations are solid.
- **No rebuild from scratch.** All gaps are forward-fixable.
- **The roadmap concept is fine** — its drift is what's broken,
  not its shape. Closing the build-note→roadmap sync loop prevents
  recurrence.
- **Texture team's deliverables are good.** The bugs are W5 engine
  bugs, not texture bugs. Mid + rock textures get reused as soon as
  C2 lands.

## Doc cap status

~340 lines (right at cap; expected since this is the single
aggregated punch-list across 4 subagent reports).
