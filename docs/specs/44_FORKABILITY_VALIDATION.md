# Spec: Forkability Validation

> Status: draft
> Tier: 3 (output / packaging)
> Depends on: 01_MODULE_LAYOUT, 06_TEST_INFRASTRUCTURE,
> 17_VERSIONING_AND_MIGRATION, 18_PLUGIN_INSTALL_AND_DEV_LOOP,
> 43_PLUGIN_PACKAGING
> Consumed by: W5 ITSELF (this is the structural test of "done")

## Purpose

The structural test of W5's success metric: **forkable into 3
projects.** Take W5, fork it into 2-3 demo projects (independent of
`demo/`), see what breaks, fix it, document the install +
iteration story.

This is the LAST gate before W5 v1 is "done." If forkability
validation passes, W5 hits its success metric. If it fails,
remaining work is whatever the validation surfaces.

## Non-goals

- Maintaining the fork projects long-term (one-time validation)
- Validating every possible consumer use case (a sample of 3 is
  the spec; pattern generalizes)
- Open-sourcing the forks (validation is internal; forks may or
  may not be published)
- Building a "consumer demo template" (the bundled `demo/` project
  serves that purpose; forkability is the proof it actually works)

## V1 validation process

### Three fork projects

Forks should exercise different consumer profiles:

1. **Fork A — "Bare minimum 3D walk"**: empty Godot project, install
   W5 via Method A (submodule, per spec 18), drop in the bundled
   `demo/` scene unchanged. Validates: install method, autoloads
   register, world bundle loads, default rendering works.

2. **Fork B — "Customized 3D walk"**: empty Godot project, install
   W5 via Method B (copy, per spec 18), customize the camera +
   substitute a custom world bundle, customize lighting recipe.
   Validates: install method B, public API is usable for
   customization, custom world bundles work, recipe override works.

3. **Fork C — "Pipeline-only consumer"**: empty Python project
   (NOT a Godot consumer), install W5's pipeline via
   `pip install -e ./pipeline` from a cloned W5 source tree
   (SA-S5.7: pip-from-PyPI deferred post-v1), generate textures +
   bake LOD chains + bake a world bundle, output consumed by Fork
   A or B. Validates: pipeline is engine-agnostic, doesn't depend on
   Godot at runtime, produces consumable output.

### Per-fork validation checklist

For each fork:

- [ ] Fresh-clone of W5 + install method completes in < 5 min
- [ ] Bundled scene loads + runs without errors
- [ ] `python -m world5.setup verify_install` returns 0
- [ ] `python -m world5.verify --fast` runs in the fork's environment
- [ ] Consumer can modify a world bundle (decoration zone edit,
      atmosphere profile swap) and see results without engine code
      changes
- [ ] Consumer can upgrade W5 to next MINOR via the spec 18 install
      method (no breakage)
- [ ] Documentation (engine/README.md, demo/README.md, spec docs)
      is enough for consumer to do all of the above without asking
      the W5 team for help

### Failure handling

If any checklist item fails:
1. Document the failure mode (which fork, which step, what broke)
2. Determine root cause: bug in W5 vs unclear documentation vs
   consumer error
3. If W5 bug: fix in W5, re-run validation
4. If doc error: clarify the relevant spec/README, re-run validation
5. If consumer error AND the doc is clear: doc this as known
   limitation in install guide
6. Re-validate until all checklist items pass

## V1 forkability sprint

Estimated: 3-5 sessions of work
- 1 session: set up the 3 fork projects (boilerplate)
- 1-2 sessions: walk through validation checklist; surface +
  document issues
- 1-2 sessions: fix surfaced bugs / doc gaps + re-validate

Output: a `docs/forkability_validation_report.md` documenting:
- Per-fork outcome (pass / partial pass / fail)
- Any W5 bugs surfaced + their fixes
- Any documentation gaps identified + their fills
- "Known limitations" list (consumer use cases NOT covered;
  out-of-scope per W5 design)

## Public API

```bash
# Run a fork's validation
python -m world5.forkability.validate --fork-path /path/to/fork_a/

# Run all forks
python -m world5.forkability.validate --all
```

JSON output for CI integration.

**What `validate --fork-path` mechanically checks** (SA-M5.8):
1. Runs spec 14 world contract on every world bundle in the fork
2. Runs spec 18 `python -m world5.setup verify_install` on the
   fork's `addons/world5/` (or equivalent install path)
3. Runs `python -m world5.verify --fast` from the fork's Python
   environment (catches broken pipeline install)
4. Reports per-checklist-item pass/fail (the human checklist from
   the V1 validation process section above)
5. Exit code 0 if all pass, 1 if any fail, JSON output describes
   which

## Per-fork directory expectation

Each fork lives in its own dir; W5 doesn't require them to be in any
specific location. Fork docs (in W5's docs/) list each fork's
purpose, install method, and verification status.

## Producer / consumer contract

- **Produces**: forkability validation report; surfaced bugs +
  fixes; documentation improvements
- **Consumes**: W5 source + the 3 fork projects (independent dirs)

## Dependencies

- All prior specs (this is the integration test of the entire engine)
- Spec 06 (`verify` is the per-fork tool)
- Spec 17 + 18 (versioning + install methods are validated)
- Spec 43 (release builds are what consumers consume)

## Quality bar

- All 3 forks pass full validation checklist
- Issues surfaced are documented + fixed before W5 v0.1.0 release
- The validation report is clear enough that a new contributor could
  reproduce the test
- After validation, W5 v0.1.0 can be tagged

## Discoverability

- **Entry point**: `python -m world5.forkability.validate`
- **Schema**: validation report shape (per-fork status table)
- **Validator / preflight**: the forkability validation IS the
  ultimate validator of the engine
- **Example**: the 3 fork projects + the validation report
- **Deterministic outputs**: yes — same fork at same W5 version
  produces same validation result

## Open questions

- **Where do the fork projects live?**: temporary scratch dirs in
  `D:/tmp/w5_forks/` during validation. Not checked into the W5
  repo (they're test fixtures, not engine code). May be open-sourced
  separately if useful.
- **Consumer-game-specific fork (the wizard game itself)**: probably
  becomes Fork D when it exists. Wizard game's needs are out of W5
  scope so it's not part of v1 validation, but its existence as a
  validation target is part of W5's purpose.
- **CI integration**: forkability validation is expensive (each fork
  is its own clone + verify). Probably runs on release tags only,
  not per-PR. Defer to plan doc.

## References

- W5 plan: success metric is "forkable into 3 projects"
- This spec is the direct response

## Revision history

- 2026-05-16: initial draft
