# Phase 4.8 — Local RD Refactor

> Phase: 4.8 (sub-phase of Phase 4)
> Status: 📋 planned
> Estimated sessions: 1-2 (focused)
> Triggered by: 2026-05-17 visual-review session — after Phase 4.7
> fixed the autoload bootstrap, walking demo STILL doesn't render
> terrain. Root cause: `GpuTerrainBackend._generate_heights` uses
> the main RenderingDevice for compute work + calls explicit
> `rd.submit() / rd.sync()`. Godot 4.6 errors:
> `"Only local devices can submit and sync."`

## Problem statement

Standalone runs fire the error continuously (one per page request).
Pages don't generate → heightmaps stay empty → terrain shader
samples a zero-default sampler2D → `VERTEX.y = (0 - 0.5) * 2 * 50 = -50`
→ entire terrain renders as a flat plane at Y=-50m. Camera at
Y=60+ looking forward/down sees mostly procedural sky's ground
color band; the flat -50m plane is below the camera's view in
most reasonable poses.

Why the gut_real_gpu test layer passes: gut launches via
`--script gut_cmdln.gd --display-driver windows`. In that mode the
test viewport's RenderingDevice is local (not the main render
target), so explicit submit/sync works. Standalone scenes use the
main RD, which Godot's renderer owns + forbids external
submit/sync.

## Decision

Use `RenderingServer.create_local_rendering_device()` in
GpuTerrainBackend instead of `RenderingServer.get_rendering_device()`.
This gives the backend its OWN device for compute work that doesn't
conflict with Godot's renderer.

## Deliverables

- [ ] `GpuTerrainBackend._compile_shader` calls
      `RenderingServer.create_local_rendering_device()` on first
      use; caches the local RD for the backend's lifetime
- [ ] `_generate_heights` uses the local RD for storage_buffer +
      compute pipeline + submit + sync + buffer_get_data
- [ ] `shutdown()` frees the local RD properly (per spec 08a rule 5)
- [ ] Update gut_real_gpu tests to verify against the local-RD path
      (probably no test changes needed — they go through the same
      backend, just now using a local RD)
- [ ] Update `engine/tests/visual/test_terrain_capture_baseline_real_device.gd`
      to assert the actual visual gate (now possible: standalone
      capture should show non-flat terrain)
- [ ] Re-enable the walking demo as a real visual deliverable
      (remove the known-issue section from `walking_demo.md`)

## Out of scope

- Changing the GPU/CPU contract spec (spec 08a) — the contract
  stays "GpuJob runs on render thread"; the backend just uses a
  local RD inside its GpuJob callback
- Texture2DRD upload pathway (TR-PERF audit recommendation; Phase
  5 — still relevant but separate from the compute-RD fix)
- Async readback split (Phase 5+)

## Risk

The local-RD approach is what Godot officially recommends for
compute work that needs explicit submit/sync. Should be a clean
refactor. Watch for:
- Local RD doesn't share resources with the main RD by default —
  if any current code shares textures across, that breaks
- Spec 08a's `GpuResourceTracker` registration still works (RIDs
  belong to whichever RD created them; the tracker just records)

## Close criteria

- Standalone run of `walking_demo.tscn` shows visibly-displaced
  terrain (hills + valleys), not a flat sky-ground band
- gut_real_gpu still green
- Phase 4.6's `walking_demo.md` known-issue section removed
- Build-note records before/after capture screenshots

## Doc cap status

~75 lines.
