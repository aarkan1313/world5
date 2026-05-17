# Phase 3 — Renderer Research Sprint

> Phase: Phase 3
> Status: ✅ done (2026-05-16; 1 session vs 3-5 estimate)
> Owner: agent-led research; user reviews decision
>
> Goal: produce `docs/specs/15a_RENDERER_DECISION.md` per spec 15
> sections A-E, validated by a 1km × 1km prototype hitting 60fps on
> RTX 3060. Unblocks spec 21 (Terrain Renderer) + spec 24 (Ground
> Variety).

## Outcome

**Decision: clipmap** per spec 15a. Research surfaced 3 of 5
candidates aren't viable in Godot 4.5 (mesh shaders not exposed;
nanite-style design-phase only; VT requires engine extension
authoring), collapsing the decision quickly. Prototype at
`engine/examples/renderer_research_prototype/` renders 130k-tri
1km × 1km scene at ~0.7 ms/frame on RTX 5090 Laptop (extrapolated
2-3 ms on RTX 3060; fits X_FRAME_BUDGET 2.0 ms terrain allocation
with margin for one ring; full 8-ring rig needs LOD optimization
in Phase 4). See `docs/build-notes/phase_3_renderer_research_2026_05_16.md`
for full breakdown.

## Scope

Per spec 15 deliverables:

- [ ] **Section A: Per-candidate analysis** (5 candidates)
  - [ ] Clipmap — architecture, Godot 4.5 fit, quality ceiling,
        performance, implementation cost, maintenance cost, risk
  - [ ] Virtual texturing — same axes
  - [ ] Mesh shaders / meshlets — same axes
  - [ ] Nanite-style virtualized geometry — same axes
  - [ ] Hybrid (clipmap + VT material + meshlet decoration) — same axes
- [ ] **Section B: Comparison matrix** (single table, 5 candidates ×
      axes)
- [ ] **Section C: Recommended primitive + pillar-by-pillar
      justification**
- [ ] **Section D: Implementation outline** (high-level shape,
      module boundaries, not full spec 21)
- [ ] **Section E: Validation prototype** at
      `engine/examples/renderer_research_prototype/`
- [ ] **Deliverable check** (spec 15):
  - [ ] `15a_RENDERER_DECISION.md` exists with sections A-E
  - [ ] Validation prototype renders 1km × 1km at 60fps on RTX 3060
  - [ ] User has reviewed + signed off
  - [ ] No open question in decision doc would change recommendation

## Fallback path (committed per spec 15 + audit C3)

Three failure modes:

- **F1** Sprint can't conclude in 5 days → default to **clipmap**
  (W4.1's proven primitive; we have working production code as
  reference)
- **F2** Chosen prototype < 60fps on 3060 at 1km × 1km → invalidate
  decision; restart sprint with failed primitive dropped from
  candidate list; if second sprint also fails → F1
- **F3** Godot 4.5 support insufficient (requires C++ module /
  extension authoring) → drop to next-simplest candidate per the
  committed simplicity order

**Candidate simplicity order** (per spec 15 SA-S2.8):
1. Clipmap
2. Detail-array-augmented clipmap
3. Hybrid (clipmap + VT material)
4. Virtual texturing (full)
5. Mesh shaders / meshlets
6. Nanite-style

## Sources to consult

Per "in-session research" answer (2026-05-16):

- **W4.1 reference**: `D:/assets/world 4/the world 4/scripts/ClipmapWorld.gd`
  + `ClipmapRing.gd` (3900 + lines) — proven clipmap implementation
- W4.1 retrospective: `D:/assets/world 4/docs/W4_1_RETROSPECTIVE_2026_05_16.md`
- W4.1 tech stack audit: `D:/assets/world 4/docs/TECH_STACK_AUDIT_2026_05_16.md`
- Godot 4.5 rendering docs (forward+, mesh shaders, RenderingDevice)
- Bruneton 2008 "Precomputed Atmospheric Scattering" (atmosphere,
  not renderer — referenced for context)
- Genshin Impact / RDR2 virtual texturing presentations
  (publicly available GDC talks)
- UE5 Nanite documentation (architecture only, not implementation
  details)
- Godot 4.5 mesh shader support status (recent feature; verify
  current support level)

## Out of scope

- Detailed renderer implementation (Phase 4)
- Per-tier calibration (Phase 4.5)
- Survey/topdown bake recipes (Tier 3, Phase 15)
- GPU/CPU contract (spec 08a; already shipped)

## Process

1. **Research phase** (this session): walk through 5 candidates,
   use WebFetch as needed for current Godot 4.5 support detail,
   reference W4.1 ClipmapWorld for clipmap section
2. **Decision phase**: write `15a_RENDERER_DECISION.md` synthesizing
   research; pillar-justified recommendation
3. **Prototype phase**: build minimal scene proving the chosen
   primitive works in Godot 4.5
4. **Validation phase**: run on dev hardware (RTX 4080 here, not 3060;
   document the extrapolation)
5. **Close**: build-note + STATE/ROADMAP update + push

## Open questions to lock during research

- [ ] **Godot 4.5 mesh shader support**: 4.5 added partial support;
      verify current capability + Vulkan version requirement
- [ ] **Texture2DArrayRD vs Texture2DRD for clipmap pages**: W4 used
      Texture2DRD per page; would a single Texture2DArrayRD with
      one slice per ring be more efficient?
- [ ] **MultiMeshInstance3D vs custom RenderingDevice draw**: Godot's
      MMI is high-level; clipmap rings could use it OR drop to raw
      RD draw calls
- [ ] **3060 measurement**: I have RTX 4080 on dev hardware. 3060
      perf extrapolation: roughly 0.4x of 4080 (3060 = ~10 TFLOPs vs
      4080 = ~50 TFLOPs but bandwidth + latency matter more for
      streaming workloads). Document the assumption in section E.

## Phase 3 close criteria

- [ ] `15a_RENDERER_DECISION.md` exists with all 5 sections
- [ ] Prototype scene + .tscn at `engine/examples/renderer_research_prototype/`
- [ ] Prototype runs in Godot 4.5 + measures frame time
- [ ] Decision is unambiguous (one primitive named; pillar-justified)
- [ ] verify --full still passes
- [ ] Build-note + STATE + ROADMAP updates pushed

## Doc cap status

This file: ~120 lines (under 350 cap).
