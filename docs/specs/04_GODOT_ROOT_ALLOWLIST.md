# Spec: Godot Project Root Allowlist

> Status: draft
> Tier: meta
> Depends on: 01_MODULE_LAYOUT
> Consumed by: every contributor + a preflight check

## Purpose

W4.1 hit the **candidates/ trap** twice: large pipeline scratch
directories (`candidates/` 9 GB, then earlier `subjects_3d/` 24 GB)
were placed inside the Godot project root. Godot's `--import`
scanned them. Editor open time + headless import time exploded.

The fix in W4.1 was to move those dirs out, retroactively, after the
trap was hit. W5 prevents repeats by codifying which directories ARE
allowed inside the Godot project root (`engine/` and `demo/`) and
enforcing it with a preflight script.

Without this spec, the next contributor adds a large generated-content
dir, the next session re-discovers the trap, and we lose hours. This
is cheap defense against a known-recurring failure mode.

## Non-goals

- Enforcing what can live in the `pipeline/` Python dir (no Godot
  scanning concern)
- Replacing `.godotignore` (we use both: allowlist + ignore)
- Auto-fixing violations (preflight reports them; humans move them)

## The allowlist

### Inside `engine/` (the Godot addon)

Permitted top-level subdirs:
- `scripts/` — `.gd`, `.cs` files
- `scenes/` — `.tscn` files
- `shaders/` — `.gdshader`, `.glsl` files
- `resources/` — `.tres`, small JSON config files
- `tests/` — gut tests
- `examples/` — minimal example scenes per system (capped per "examples
  size cap" below)
- `addons/` — third-party Godot addons (e.g. gut itself), if any
- `decoration_meshes/` — shipped LOD-baked decoration meshes (spec 27)
- `foliage_meshes/` — shipped foliage trunks + leaf cards (spec 29)
- `cave_meshes/` — shipped REUSABLE cave-specific assets only
  (stalactites, entrance arches, decorative cave props consumed by
  cave decoration). SA-M4.11: per-chunk procedurally-generated cave
  geometry lives in world bundles at `worlds/<world>/cave_chunks/`,
  NOT here. This dir is for the engine-bundled reusable library.
- `worlds/` — shipped reference world bundles (the bundled demo world(s))

Permitted top-level files:
- `plugin.cfg` — Godot addon manifest
- `README.md` — addon how-to
- `LICENSE` — addon license
- `CHANGELOG.md` — semver changelog (spec 17 + 43)
- `RELEASE_NOTES.md` — per-release narrative (spec 43)
- `INSTALL.md` — install methods (spec 18)
- `MIGRATION.md` — present only on MAJOR releases (spec 17)

**NOT permitted in `engine/`:**
- Pipeline scratch (texture candidates, mesh variants, intermediate
  bakes, generation logs)
- Asset libraries that aren't the SHIPPED runtime asset set (e.g.
  candidate textures awaiting review)
- DEM source data / reference imagery
- Backup zips
- Python venvs / model checkpoints / weights

### Inside `demo/` (the consumer Godot project)

Permitted top-level subdirs:
- `addons/` — the W5 plugin install + any third-party addons used by
  demo scenes
- `scenes/` — `.tscn` files for demo scenes
- `worlds/` — small demo-world bundles (kept small; large content goes
  in `pipeline/` outputs and references)
- `scripts/` — demo-specific GDScript
- `resources/` — demo-specific `.tres`

Permitted top-level files:
- `project.godot`
- `README.md`
- `LICENSE`

**NOT permitted in `demo/`:**
- Pipeline outputs that aren't actively being demoed (intermediate
  files, candidate variants)
- Build artifacts (export presets are fine; built binaries are not)
- Anything Godot will spend time importing that isn't actually
  consumed by a demo scene

### Outside `engine/` and `demo/` (the rest of `world 5/`)

Everything else lives here. No Godot scanning concern. Specifically:
- `pipeline/` — Python pipeline + outputs that don't ship in the addon
- `tools/` — one-off scripts, debugging utilities
- `docs/`, `tests/`, etc.

## Preflight enforcement

`pipeline/world_contract/godot_root_check.py` (or equivalent) is a
Python script that:
1. Walks `engine/` and `demo/` and lists all top-level entries
2. Compares against this allowlist
3. Fails (exit 1) if any disallowed entry is found
4. Optionally: prints suggested location (e.g. "move `candidates/` to
   `pipeline/textures/candidates/`")

Run as part of `python -m world5.verify`. CI / pre-commit hook can
also gate on it.

**A violation does not auto-resolve**: the script reports and exits.
Humans/agents must move the directory + update the references.

## Public API

CLI:
```
python -m world5.world_contract.godot_root_check [--engine engine/] [--demo demo/]
```

Exit codes:
- `0` — all clear
- `1` — disallowed entries found (printed to stdout)
- `2` — config / argument error

JSON output mode (`--json`) for LLM consumption:
```json
{
  "engine": {
    "allowed": ["scripts/", "scenes/", ...],
    "violations": [
      {"path": "engine/scratch/", "suggestion": "move to pipeline/scratch/"}
    ]
  },
  "demo": {...}
}
```

## Producer / consumer contract

- **Produces**: the allowlist itself (this doc + a machine-readable
  copy in `pipeline/world_contract/godot_root_allowlist.json` for the
  preflight script).
- **Consumes**: the directory state of `engine/` and `demo/`.

## Dependencies

- `01_MODULE_LAYOUT` (defines `engine/` and `demo/` existence)

## Quality bar

- `godot_root_check` runs in < 1 second on a clean tree
- Zero false positives on a freshly-cloned W5 repo
- The script's JSON output is parseable + actionable by an LLM agent
  (the suggestion field tells where to move the violation)
- Spec text + JSON copy stay in sync (spec gets revision history, JSON
  has version field)

## Discoverability

- **Entry point**: `pipeline/world_contract/godot_root_check.py` CLI
- **Schema**: `pipeline/world_contract/godot_root_allowlist.json` is
  the machine-readable allowlist + violation-suggestion table
- **Validator / preflight**: the script IS the validator; runs as
  part of `python -m world5.verify`
- **Example**: a violation looks like `engine/candidates/` (any
  dir not in the allowlist); the suggested fix is in the JSON output
- **Deterministic outputs**: yes — same tree state produces same
  violation list

## Examples size cap (committed)

Audit M15 finding: `engine/examples/<system_name>/` becomes a
candidates trap if every system ships textured TRELLIS subjects + LOD
chains. Cap committed in v1:

- **Per-example cap**: any single `engine/examples/<name>/` may not
  exceed **20 MB** total
- **Aggregate cap**: total of all `engine/examples/` may not exceed
  **100 MB**

Example scenes should reference assets from `engine/decoration_meshes/`
or `engine/worlds/` rather than ship copies. Preflight enforces both
caps.

## Shipped-mesh dir caps

`decoration_meshes/`, `foliage_meshes/`, `cave_meshes/` are runtime
assets — they MUST be in the addon for the engine to work. They are
exempted from the candidates-trap concern but they have their own
caps:

- `decoration_meshes/`: hard cap at **2 GB** (review per-subject when
  approaching)
- `foliage_meshes/`: hard cap at **1 GB**
- `cave_meshes/`: hard cap at **500 MB**
- `worlds/`: hard cap at **500 MB** for the bundled demo world(s);
  larger consumer worlds live in `demo/worlds/` or the consumer's
  own project

If a cap is approached, preflight warns; preflight fails at 1.25× cap.

## Open questions

- Should we also check file *size* (e.g. flag any single file in
  `engine/` > 50 MB)? Probably yes but defer to v0.2; first version
  just checks dir names + the caps above.

## References

- W4.1 memory entry: `w4_godot_root_no_big_assets` (the trap and
  its history)
- W4.1 PITFALLS #16 (Godot launcher trap from unquoted project path —
  related but different failure mode)

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (C7 + M15). Added shipped-mesh dirs
  (decoration_meshes/, foliage_meshes/, cave_meshes/, worlds/) and
  release-doc files (CHANGELOG, RELEASE_NOTES, INSTALL, MIGRATION) to
  the allowlist. Committed examples size cap (20 MB per, 100 MB total).
  Added per-dir caps for shipped-mesh dirs.
