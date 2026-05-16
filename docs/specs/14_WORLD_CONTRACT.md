# Spec: World Contract / Preflight

> Status: draft
> Tier: cross-cutting (Tier 0)
> Depends on: 01_MODULE_LAYOUT, 13_QUALITY_TIERS
> Consumed by: every world bundle (`worlds/<name>/`); CI; pre-launch checks

## Purpose

A validator that checks a `worlds/<name>/` bundle before runtime
consumes it. Catches schema violations + cross-system inconsistencies
+ tier-budget overruns at preflight time, not at runtime.

W4.1 had this (`pipeline/world_contract.py`); proven pattern. W5 keeps
the shape but extends coverage to every system (W4.1's contract grew
incrementally to cover only the systems it had).

The checks: biome catalog uniqueness, kit paths exist + sized
correctly, `biome_scale_m` matches kernel system, shader cap not
exceeded, PBR map presence + tier-correct sizes, surface slot rules
self-consistent, material variant manifests sane, optional macro
albedo companions present if claimed, generator params (noise_stack,
erosion etc) parseable, elevation range fact-checked, and every other
contract any system declares.

## Non-goals

- Runtime content validation (we trust authored content that passes
  preflight)
- Style / aesthetic critique (humans + visual review)
- Auto-fixing violations (preflight reports; humans fix)
- Validating consumer (`demo/`) projects (only world bundles get
  contract checks)

## World bundle shape

```
engine/worlds/<world_name>/         # engine-shipped reference worlds
                                    # (bundled demo world(s); SA-M2.7)
or
<consumer_project>/worlds/<world_name>/  # consumer-authored worlds
                                          # (e.g. demo/worlds/ or
                                          # wizard_game/worlds/)
├── world.json                      # bundle manifest
├── biome_catalog.json              # biomes + slots + maps
├── surface_slots.json              # ground/mid/rock rules
├── material_variants.json          # sibling-variant manifest
├── materials/
│   └── biome_<biome>/
│       ├── ground/                 # albedo, normal, roughness, ao, macro_albedo
│       ├── mid/
│       └── rock/
├── kernels/                        # optional per-world kernel config
│   └── noise_stack.json
├── decorations/                    # baked decoration blobs (output of bake)
├── biome_decoration/               # decoration palette per biome
├── decoration_overrides.json           # author-override zones
└── README.md                       # human-readable description
```

## Public API

### CLI

```
python -m world5.world_contract --world <path> [--strict] [--tier high] [--json]

  --strict        Fail on warnings, not just errors
  --tier          Validate against this tier's budgets (default: high)
  --json          Machine-readable output
```

Exit codes:
- `0` — passed
- `1` — errors found
- `2` — warnings found AND `--strict` set
- `3` — argument / config error

### Python: `pipeline/world_contract/__init__.py`

```python
from world5.world_contract import validate, ContractResult

result: ContractResult = validate(
    world_path=Path("demo/worlds/two_biome/"),
    tier="high",
    strict=True,
)
if not result.passed:
    print(result.errors)
    sys.exit(1)
```

### Checks per-system

Each system spec declares its world-contract requirements in its
Quality bar section. The world_contract module collects these and
runs them. New system → its spec adds checks → contract grows
automatically.

Examples (declared in respective specs):
- **Biome catalog spec**: `biome_catalog.json` schema valid, biome
  names unique, slot names match `surface_slots.json`
- **Materials spec**: every biome × slot path exists, PBR maps
  present, sizes match tier
- **Decoration spec**: `biome_decoration/*.yaml` schema valid, mesh
  IDs reference existing meshes in addon, zone bounds within world
  extent
- **Quality tiers spec**: tier config validates against schema
- **Kernel spec**: noise stack params parseable, kernel produces
  bounded heights for declared elevation range

## Strict mode

Default: errors fail, warnings pass. Strict: warnings also fail.
Used in CI to catch slow drift before runtime.

Common warnings (don't fail by default):
- Macro albedo companion missing (optional system; warn so author
  knows about it)
- Material variant siblings only 1 per slot (legal but loses variety)
- Biome decoration palette empty (legal but means no decoration in
  that biome)

Common errors (always fail):
- Schema violation (malformed JSON, missing required key)
- Mesh ID referenced that doesn't exist
- Tier budget exceeded by world's estimated PBR memory
- Biome name duplicated in catalog
- Slot name in palette doesn't exist in `surface_slots.json`

## Producer / consumer contract

- **Produces**: validation reports (CLI + JSON)
- **Consumes**: world bundle directory + tier name

## Dependencies

- `01_MODULE_LAYOUT` (placement)
- `13_QUALITY_TIERS` (tier-budget checks)
- Each system's spec contributes its own checks

## Quality bar

- Validation of a typical world bundle (4 biomes, 30 PBR layers,
  decoration palette) completes in < 5s
- Zero false-positive failures on a clean reference world
- Errors are actionable (point at the specific file + line + key)
- JSON output is parseable by an LLM agent for self-correction
  workflows
- 100% pytest coverage of every check

## Discoverability

- **Entry point**: `python -m world5.world_contract --world <path>`
- **Schema**: per-system JSON Schemas at
  `engine/resources/schemas/*.json` (referenced by the validator)
- **Validator / preflight**: this spec IS a validator; it self-checks
  via pytest
- **Example**: `engine/examples/example_world/` is a minimal valid
  world bundle; `engine/examples/example_world_broken/` is a deliberately
  broken one (for testing the validator's error reports)
- **Deterministic outputs**: yes — same world bundle + same tier always
  produces same report

## Open questions

- **Per-system check registration**: each spec's checks can either
  (a) live in the spec doc + be manually copied to `world_contract/checks/<system>.py`,
  or (b) be auto-discovered via a decorator. (b) is cleaner. Decide
  during implementation.
- **Performance**: should checks run in parallel? Probably yes for
  large worlds; defer until measured.

## References

- W4.1 `pipeline/world_contract.py` — proven pattern; carry over the
  shape (modular checks, strict mode, tier-aware) but refactor for
  per-system declared checks instead of monolithic
- W4.1 retrospective: world contract was one of the highlights — the
  preflight pattern caught real bugs before runtime

## Revision history

- 2026-05-16: initial draft
- 2026-05-16: post-audit (C8). Renamed `decoration_zones.json` →
  `decoration_overrides.json` to match spec 39's unified override
  envelope convention.
