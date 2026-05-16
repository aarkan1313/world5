# Spec: Versioning + Migration

> Status: draft
> Tier: meta
> Depends on: 01_MODULE_LAYOUT, 12_CONTENT_ADDRESSING
> Consumed by: every baked artifact, every consumer fork, plugin packaging

## Purpose

The success metric is "usable, exportable, swappable, easy to adapt
and tune for whatever." Without a versioning + migration story, a
consumer that pins to W5-v0.3 has no path to W5-v0.5 — every baked
world breaks, every spec contract shifts silently, no upgrade is
safe.

W4.1 had partial version stamps (decoration blobs carried
`w4_version`, terrain pages carried generator + kernel hashes) but no
formal cross-engine migration story. Consumer projects couldn't pin
or migrate.

W5 commits to **semantic versioning + version-stamped artifacts +
explicit migration scripts** so consumers can pin, upgrade, and know
exactly what changed.

## Non-goals

- Backwards compatibility forever — we ship migration scripts, not
  permanent shims
- Cross-Godot-version migration (W5 pins to Godot 4.5+; major Godot
  version changes are a different concern)
- Consumer-game save-state migration (consumer responsibility; W5
  provides hooks)

## Versioning scheme

**Semver**: `MAJOR.MINOR.PATCH`.

- **MAJOR**: breaking spec contract changes. A consumer MUST run
  migration script to upgrade. Rare.
- **MINOR**: new features, additive contract changes. Existing
  consumers continue to work; new capabilities available if opted into.
- **PATCH**: bug fixes, no contract change. Drop-in upgrade.

Pre-1.0: anything goes. Major = could break things. The W5 versioning
contract becomes load-bearing at 1.0.

## Where the version lives

**Single source of truth**: `engine/plugin.cfg` has the version field.
Everything else reads from it.

Build-time:
- `pipeline/core/version.py` exposes `WORLD5_VERSION = "0.1.0"` etc.
  (auto-generated from plugin.cfg at build).
- GDScript: `World5.VERSION` (autoload constant, populated at boot).
- Every baked artifact embeds the building version in its header /
  metadata.

## What gets version-stamped

Every baked artifact carries enough version info that a loader can
detect mismatch:

```json
{
  "w5_version": "0.3.2",
  "w5_min_compatible": "0.3.0",       // older readers fail; newer OK if MINOR/PATCH
  "schema_version": 1,                 // per-artifact schema (e.g. decoration blob v2)
  "content_address_keys": {            // (from spec 12)
    "kernel_hash": "...",
    "pipeline_version": "0.1.0",
    ...
  }
}
```

Loaders check:
- If reading artifact's `w5_version` MAJOR ≠ runtime MAJOR → migration
  required (refuse to load until migrated)
- If artifact's `w5_min_compatible` > runtime version → reader is too
  old → consumer must upgrade W5
- If `schema_version` is older than current reader → in-memory upgrade
  if supported, else migration required

## Migration scripts

When a MAJOR or breaking-MINOR change ships, an explicit migration
script lives at `pipeline/migrations/v<from>_to_v<to>.py`:

```python
# pipeline/migrations/v0_3_to_v0_4.py
"""W5 0.3 → 0.4 migration.

Breaking changes:
- decoration blob format v2 → v3 (added cluster_id field)
- biome_catalog.json key 'biome_scale' renamed to 'biome_scale_m'
- world.json gained required 'seed' field

This script:
1. Reads every artifact in <world_path>
2. Rewrites in v0.4 format
3. Updates the world.json version stamp
"""

def migrate(world_path: Path, dry_run: bool = False) -> MigrationResult: ...
```

CLI:
```
python -m world5.migrate --world <path> --to 0.4.0 [--dry-run]
```

JSON output for LLM consumption + scripted migrations.

## Migration policy

- Every MAJOR or breaking-MINOR ships with a migration script. **No
  exceptions.** If we can't write the migration, we don't ship the
  break.
- Migration scripts are append-only (v0.3→v0.4 ships once, never
  changes). Chain migrations: a v0.1 world goes through 0.1→0.2,
  0.2→0.3, 0.3→0.4 to reach 0.4.
- Migration scripts are tested: each ships with a pytest fixture
  containing a "from"-version sample world + the expected
  "to"-version output.
- **No retro-edits to past schema versions** (SA-S2.10). If we
  discover a bug in v0.2's schema after v0.3 ships, we don't edit
  v0.2 — we ship a v0.3.1 (PATCH) with a "fixup" migration that
  cleans the malformed-on-disk artifacts and re-derives the
  expected v0.3 shape. This preserves the property that a v0.1→
  v0.2→v0.3 chain always lands at the same v0.3 shape regardless
  of when the user runs it.

## Plugin install + version pinning (consumer side)

Consumer projects pin to a W5 version via the plugin install method
(symlink / git-submodule / copy — per spec 18). Standard install
flow:

```
# Consumer wants to pin to W5 v0.3.2
git submodule add -b v0.3.2 https://.../world5 demo/addons/world5
```

On Godot project load, the W5 plugin checks if any world bundle's
`w5_version` is incompatible with the installed plugin and surfaces
a clear error pointing at the migration command.

## Public API

### Python: `pipeline/core/version.py`

```python
WORLD5_VERSION: str = "0.1.0"  # auto-generated from plugin.cfg

def parse(version_str: str) -> tuple[int, int, int]: ...
def is_compatible(artifact_version: str, runtime_version: str) -> bool: ...
def needs_migration(artifact_version: str, runtime_version: str) -> bool: ...
def migration_path(from_v: str, to_v: str) -> list[str]: ...
```

### GDScript: `engine/scripts/core/World5.gd`

```gdscript
class_name World5 extends Node
# Singleton autoload at /root/World5

const VERSION: String = "0.1.0"  # populated from plugin.cfg at boot

static func parse(version_str: String) -> Array[int]
static func is_compatible(artifact_version: String) -> bool
static func needs_migration(artifact_version: String) -> bool
```

### Migration CLI

```
python -m world5.migrate --world <path> --to <version> [--dry-run] [--json]
```

## Producer / consumer contract

- **Produces**: version stamps on every baked artifact; migration
  scripts that bring older artifacts forward
- **Consumes**: artifact version stamps at load time; runtime version
  from plugin.cfg

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `12_CONTENT_ADDRESSING` (content stamps include version)

## Quality bar

- Version check at artifact load: < 100µs
- Migration of a 4-biome / 30-PBR-layer world: < 30s
- Every MAJOR/breaking-MINOR has a migration script tested with
  before/after fixtures
- Migration scripts are idempotent (running twice on same artifact =
  no change)
- Migration CLI output (JSON mode) is parseable by an LLM agent for
  unattended upgrades
- 100% pytest coverage of version helpers + migration tests for every
  shipped migration

## Discoverability

- **Entry point**: `World5.VERSION` (GDScript) or `WORLD5_VERSION`
  (Python); migration via `python -m world5.migrate`
- **Schema**: artifact version header shape documented in this spec;
  per-artifact schema docs in their specs
- **Validator / preflight**: world contract preflight checks all
  artifacts in a world have compatible versions; flags missing
  migrations
- **Example**: `pipeline/migrations/_example_v0_1_to_v0_2.py` ships as
  a template for future migrations
- **Deterministic outputs**: migrations are deterministic + idempotent

## Open questions

- **Pre-1.0 policy**: probably "anything goes; migrations not
  required." Re-evaluate at 1.0.
- **Backward-load tolerance**: should a v0.5 reader try to load a
  v0.4 artifact in-memory (transient migration) without writing?
  Probably yes for MINOR-only differences; no for MAJOR.
- **Long migration chains**: if consumer is 10 versions behind, do
  we run all 10 migrations sequentially, or have a fast-path
  "v0.1 → v1.0" combined script? Probably sequential (simpler, each
  individually tested).

## References

- W4.1 decoration blob format v1→v2 (the migration we did in W4.1
  without a formal contract — auto-upgrade on read worked but was
  ad-hoc)
- semver.org for the versioning rules
- Common practice in major game engines (Unreal asset versioning,
  Unity asset bundle migration)

## Revision history

- 2026-05-16: initial draft
