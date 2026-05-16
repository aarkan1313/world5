# Spec: Plugin Packaging + Distribution

> Status: draft
> Tier: 3 (output / packaging)
> Depends on: 01_MODULE_LAYOUT, 17_VERSIONING_AND_MIGRATION,
> 18_PLUGIN_INSTALL_AND_DEV_LOOP, 06_TEST_INFRASTRUCTURE
> Consumed by: distribution mechanism (git submodule, addon store
> in the future); consumer projects

## Purpose

The mechanics of shipping W5 as a real, distributable Godot addon.
Spec 18 covered install + dev loop (what consumers do); this spec
covers the BUILD side — how W5 ITSELF produces a clean, versioned,
release-ready addon.

V1 ships:
- A reproducible build of the W5 addon
- Semver versioning of every release (per spec 17)
- An install verifier that consumers + CI can run
- Release notes + changelog discipline
- (Future) Godot Asset Library publication path

## Non-goals

- Godot Asset Library publication in v1 (defer until W5 is mature
  enough to be useful to external consumers; probably 1.0+)
- Auto-update mechanism for installed plugins (consumer's choice of
  install method dictates update flow)
- Multi-version coexistence (one W5 version per consumer)
- Pre-built binaries (W5 is pure GDScript + Python; no compile step)

## Release build contract

A "release build" of W5 produces:
- **`engine/`** subdir — exactly the W5 addon (plugin.cfg, scripts/,
  scenes/, shaders/, resources/, examples/, README.md, LICENSE)
- **`pipeline/`** subdir — the Python pipeline (optional install
  per consumer's needs). Includes a `pyproject.toml` (SA-S5.7) so
  consumers can `pip install -e ./pipeline` for editable install from
  source. PyPI upload deferred to post-v1; v1 distribution is
  source-only via the release artifact or git clone.
- **`CHANGELOG.md`** — what changed in this version (semver per spec 17)
- **`RELEASE_NOTES.md`** — human-friendly per-release narrative
- **`INSTALL.md`** — install methods (per spec 18)
- **`MIGRATION.md`** — if MAJOR bump, what consumers need to do

These are produced by `python -m world5.release.build --version 0.1.0`
and packaged into a tagged git release.

## Release process

```bash
# 1. Validate everything
python -m world5.verify --full          # spec 06 — full verify suite

# 2. Cut release
python -m world5.release.build --version 0.1.0

# 3. Tag in git
git tag -a v0.1.0 -m "W5 0.1.0 — initial release"
git push --tags

# 4. Update top-level CHANGELOG.md + RELEASE_NOTES.md (manual write)

# 5. Optional: publish to Godot Asset Library (deferred until 1.0+)
```

CI runs `verify --full` on every PR + on every tagged release. No
release tags ship without verify green.

## Install verifier

Per spec 18, consumers run:

```bash
python -m world5.setup verify_install /path/to/my_game_project/
```

This checks:
- `addons/world5/` directory exists + is correctly linked (symlink
  resolved, submodule synced, or copy present)
- W5 version in `addons/world5/plugin.cfg` matches what consumer
  expects
- Required autoloads can be loaded by Godot
- World contract checks pass on any worlds in the consumer's project

Exit codes per spec 06. JSON output for LLM consumption.

## Version bumping rules (codified)

Per spec 17:
- MAJOR: breaking spec contract changes; migration script required
- MINOR: additive features; existing consumers continue to work
- PATCH: bug fixes; no contract change

Release-time the build script auto-derives the version from
`engine/plugin.cfg` and runs migration-script existence check if
MAJOR/MINOR bumped.

## Changelog discipline

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/)
format:

```markdown
## [0.2.0] - YYYY-MM-DD

### Added
- Foliage system trunks (spec 29 Phase A)

### Changed
- Decoration runtime perf: per-instance LOD switched to dither
  (no more pops)

### Deprecated
- Old `decoration_zones.json` v0 format (use v1)

### Removed
- (none)

### Fixed
- (bug list)

### Security
- (none)
```

Every PR that ships content updates `CHANGELOG.md` in its
"Unreleased" section. Release-time, "Unreleased" gets renamed to
the version.

## Public API

### CLI

```bash
python -m world5.release.build [--version X.Y.Z] [--dry-run]
python -m world5.setup verify_install <consumer_path> [--json]
```

### Output structure (release artifact)

```
world5-0.1.0/
├── engine/                # the addon (drop into addons/world5/)
├── pipeline/              # optional Python pipeline
├── docs/                  # docs (subset; not all internal dev docs)
├── CHANGELOG.md
├── RELEASE_NOTES.md
├── INSTALL.md
├── MIGRATION.md           # only present on MAJOR bumps
├── LICENSE
└── README.md
```

### Consumer install from release artifact (SA-M5.6)

A consumer downloading `world5-0.1.0.zip`:

```bash
unzip world5-0.1.0.zip
# Engine install (per spec 18 Method B / copy):
cp -r world5-0.1.0/engine/ my_game_project/addons/world5/
# Optional pipeline install:
pip install -e world5-0.1.0/pipeline/   # editable install
# Verify:
cd my_game_project && python -m world5.setup verify_install .
```

**Do NOT** copy the entire `world5-0.1.0/` to `addons/world5/` — only
the `engine/` subdir is the addon. Docs and pipeline live elsewhere.

## Producer / consumer contract

- **Produces**: a tagged git release + release artifact dir
- **Consumes**: the engine + pipeline + docs subdirectories of W5
  source tree; current version per plugin.cfg

## Dependencies

- `01_MODULE_LAYOUT` (defines what's in the engine/ tree)
- `17_VERSIONING_AND_MIGRATION` (semver + migration discipline)
- `18_PLUGIN_INSTALL_AND_DEV_LOOP` (install methods consumers use)
- `06_TEST_INFRASTRUCTURE` (verify --full gates releases)

## Quality bar

- Release build (without verify): ≤ 60s on dev hardware
- `verify --full` runs before every release (spec 06)
- Every release tagged in git with semver tag
- CHANGELOG.md never gets out of sync with releases (CI check:
  unreleased section exists; version table in changelog matches
  git tags)
- Install verifier: 100% accurate (no false positives on a
  correctly-installed plugin; catches every kind of broken install)

## Discoverability

- **Entry point**: `python -m world5.release.build` (maintainer);
  `python -m world5.setup verify_install` (consumer)
- **Schema**: release artifact directory structure above
- **Validator / preflight**: `verify --full` is the gate; install
  verifier is the consumer-side check
- **Example**: `world5-0.1.0/` reference layout above
- **Deterministic outputs**: yes — release build from a tagged commit
  produces same artifact bit-for-bit (within filesystem ordering
  tolerances)

## Open questions

- **Godot Asset Library publication**: process is manual (upload zip,
  fill metadata, wait for approval). Defer until 1.0+. Schema-level
  ready (asset_library_metadata.json reserved slot).
- **Pre-release / beta versions**: semver supports `0.1.0-beta.1`.
  Probably useful; defer specifics.
- **Multi-platform**: W5 is Godot 4.5+ which supports Windows /
  Mac / Linux / Web. No platform-specific build needed (pure scripts).
  Just verify Godot 4.5+ on each target.

## References

- Spec 17 (versioning + migration), 18 (install + dev loop), 06 (test
  infra) — all directly upstream
- semver.org, Keep a Changelog
- Godot Asset Library publication docs

## Revision history

- 2026-05-16: initial draft
