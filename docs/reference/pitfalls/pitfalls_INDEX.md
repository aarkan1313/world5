# W5 Pitfalls — Symptom Index

> Look up bugs by symptom → cause → fix. Per spec 05 doc architecture:
> this file is the index; per-tier pitfall files carry detail.
>
> Cap: ≤ 300 lines (discipline; once approached, split into more tiers).
> Last updated: 2026-05-17.

## How to use

1. Search this index for a symptom matching what you're seeing
2. Follow the link into the per-tier file for full diagnostic + fix
3. If nothing matches, you're hitting something new — read on for the
   pitfall template at the bottom and add a new entry

## Per-tier pitfalls files

- [pitfalls_meta.md](pitfalls_meta.md) — meta + Tier 0 (build, test,
  packaging, docs, lint)
- [pitfalls_core.md](pitfalls_core.md) — Tier 1 (terrain, materials,
  decoration, foliage, atmosphere, lighting, kernels, textures)
- [pitfalls_world.md](pitfalls_world.md) — Tier 2 (water, weather,
  caves, deformation, persistence, impostors, roads)

(Per-tier files are empty placeholders until pitfalls surface during
code work.)

## W4.1 carry-over

W4.1's `PITFALLS.md` is at
[`../../../../world 4/docs/reference/PITFALLS.md`](../../../../world%204/docs/reference/PITFALLS.md).
**Do not auto-copy.** Each W4.1 pitfall is reviewed at the relevant
spec promotion (e.g. W4.1 #1 luma-floor is reviewed when spec 25
texture pipeline promotes). If a W4.1 pitfall is still relevant in W5,
carry it forward with revised diagnostic + fix.

Known W4.1 pitfalls that will likely apply to W5 (carry-over candidates
at relevant phase):
- **#10 WorkerThreadPool shutdown spam** → spec 07 Job system already
  designed to prevent this (Job._exit_tree drains queue)
- **#1 Near-black speckle on terrain** → spec 25 texture pipeline has
  luma-floor check in QA gates
- **#5/5b Godot Texture2DArray pitfalls** → spec 23 materials uses
  Texture2DArrayRD; carry over the lessons at Phase 4+
- **#6/6b Per-tile splat hard-line at boundaries** → spec 23 + spec 24
  use world-spanning splat sampler (avoids the trap by construction)
- **#16 Godot launcher unquoted path** → spec 04 allowlist enforces
  layout; this is a workflow trap not a code trap

## Pitfall entry template

When adding a new pitfall to a per-tier file:

```markdown
## #N — Short descriptive title

**Symptom**: what you see (1-3 sentences). Include error messages,
unexpected outputs, visual artifacts. The text someone would grep for.

**Cause**: what's actually happening. Root cause analysis, not the
shallow "X was set wrong" — explain why X was wrong.

**Fix**: the working solution. Code snippet or steps.

**What didn't work**: things you tried first that didn't fix it. Saves
the next person from repeating dead ends.

**Diagnostic**: how to confirm you're hitting THIS bug vs a similar
one. Specific commands, log lines, files to check.

**Related**: links to other pitfalls if this is a family. Spec
references.

**First hit**: YYYY-MM-DD, what phase / spec was being implemented.
```

Pitfall numbers are per-tier-file local (pitfalls_core.md #1, #2, ...;
pitfalls_world.md #1, #2, ...). Index here lists by short title +
links into the per-tier file.

## Live pitfall index

| # | Title | Tier | Spec | Phase |
|---|---|---|---|---|
| meta-1 | [Static methods named `get`/`load`/etc. shadow Godot builtins](pitfalls_meta.md#1) | meta | 13 | 2.3 |
| meta-2 | [`--headless` disables RenderingDevice; use `--display-driver windows` for GPU tests](pitfalls_meta.md#2) | meta | 06, 08a | 2.5 |
| meta-3 | [GDScript Dictionary iteration during erase is undefined; snapshot keys first](pitfalls_meta.md#3) | meta | 07, 11 | 2-audit |
| meta-4 | [Autoload name collides with class_name global; use W5_ prefix + W5Lookup helper](pitfalls_meta.md#4) | meta | 07, 08a | 4.7 |
| meta-5 | [Main RD rejects submit/sync in Godot 4.6; use create_local_rendering_device()](pitfalls_meta.md#5) | meta | 08a, 20 | 4.8 |
| core-1 | [Clipmap rings frustum-culled — ArrayMesh.custom_aabb ignored; set on MeshInstance3D](pitfalls_core.md#1) | core | 21 | 5.4 |
| core-2 | [Clipmap ring meshes need vertex normals; auto-computed degenerates to black](pitfalls_core.md#2) | core | 21 | 5.4 |
| core-3 | [Clipmap ring triangle winding must be front-facing from above (tl,tr,bl + tr,br,bl)](pitfalls_core.md#3) | core | 21 | 5.4 |

## Doc cap status

This file: ~85 lines (well under 300 cap).
