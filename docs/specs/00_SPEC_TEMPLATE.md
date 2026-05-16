# Spec: {SYSTEM_NAME}

> Status: draft | reviewed | shipped
> Tier: meta | cross-cutting (Tier 0) | 1 (core) | 2 (world) | 3 (output / packaging)
> Depends on: list of other spec docs
> Consumed by: list of other systems

<!-- SA-M1.1: tier vocabulary aligned to what every real spec uses
     (was previously a placeholder vocabulary that no real spec
     followed). Status enum: see spec 02 for transitions. -->

<!-- LLM-drivability note (SA-M2.9): every spec MUST add to its
     Discoverability section a line of the form:
     "Logs at level X under system_name='<canonical_name>' for these
     events: <list>"
     The canonical_name is the short tag used in spec 16 Log calls
     (≤ 15 chars; e.g. "terrain", "decoration", "asset_stream"). -->

<!-- Frame budget note: every render-touching spec's Quality bar MUST
     reference X_FRAME_BUDGET.md and quote the authorized allocation:
     "≤ X.X ms per frame at `high` tier (authorized by X_FRAME_BUDGET.md)" -->

<!-- ChangeBroadcast note: every spec that publishes a new source
     string MUST add the source name + metadata schema to spec 11's
     "Source metadata schemas" section. -->

<!-- Audio tag note: every spec that emits audio tags MUST add the
     tag list to spec 34's "Canonical tag registry" section. -->

## Purpose

One paragraph. What does this system do, and why does it exist in W5?
If it didn't exist, what would break or be worse?

## Non-goals

Bullet list. Explicit things this spec does NOT cover. Used to keep
scope tight and prevent feature creep.

## Public API (cross-cutting specs only; skeleton for vertical specs)

What other systems see. Functions, classes, configuration files, CLI
commands. Cross-cutting specs list the full API; vertical specs list
broad strokes only.

## Producer / consumer contract

What does this system produce? What does it consume? Both in concrete
terms (file formats, data structures, signals).

## Dependencies

What other systems must exist (or have stable contracts) before this
one can be built.

## Quality bar

How will we know it's done well? Measurable where possible:
- Performance bounds (frame time, memory, draw calls)
- Test coverage requirements
- Visual quality criteria (for renderer-touching specs)
- API stability commitments

## Discoverability

How does a fresh reader (human OR LLM) find + use this system?
- **Entry point**: which file/class/function does a consumer start at?
- **Schema**: where is the input/output schema (JSON Schema, Pydantic
  model, GDScript export)?
- **Validator / preflight**: what command checks "is my use of this
  correct"?
- **Example**: where's a minimal working example?
- **Deterministic outputs**: same inputs produce same outputs (required
  for LLM-drivability)?

Every spec must answer these so the engine stays navigable to humans
and agents alike. See `03_PILLARS.md` (LLM-drivability is a property
of every system).

## Open questions

Things we know we haven't decided yet. Block other specs if listed
here, get resolved in subsequent spec passes.

## Implementation phases (when promoted to plan doc)

Skip in spec. Goes in the implementation plan when the spec moves to
"reviewed" → "shipped."

## References

- W4.1 equivalent (link to W4.1 file if there's prior art to learn from)
- External references (papers, AAA techniques, library docs)
- Related W5 specs

## Revision history

- YYYY-MM-DD: initial draft
- ...
