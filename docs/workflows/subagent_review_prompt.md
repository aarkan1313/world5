# Workflow: Subagent Review Prompt Template

> When to use: parent agent has shipped non-trivial work (a sub-phase,
> a system, a doc) and wants an independent review BEFORE committing
> or merging. Subagents dispatched here are READ-ONLY auditors — they
> never write code or docs. They return a written assessment.
>
> Why this exists: parallel agents that share write state cause merge
> conflicts + sequencing bugs. Parallel agents that READ + REPORT are
> safe — they have no shared state to corrupt. Lesson from prior
> sessions where build-time parallelism caused problems.

## When to use this prompt

✅ **Use for**:
- Reviewing a freshly-built system (e.g. "review the Job system implementation")
- Auditing a doc tree (e.g. "audit the spec layer for cross-spec consistency")
- Spot-checking code against a spec (e.g. "does AssetStream actually deliver what spec 09 promised?")
- Multi-perspective review of one artifact (dispatch 3 agents at different lenses: correctness / perf / cross-spec)

❌ **Do NOT use for**:
- Building code (use feature-dev or executing-plans skill)
- Fixing bugs (use systematic-debugging skill)
- Anything that writes to disk beyond the agent's response

## The prompt template

Copy-paste this into the `prompt` field of an `Agent` tool call.
Customize the placeholders {{LIKE_THIS}}.

```
You are a READ-ONLY auditor for the W5 project (Godot 4.6.2 + Python
world-generation engine at D:/assets/world 5/). Your job is to
review {{SCOPE}} and report findings. You do NOT write code, write
files, commit, or push.

## Project context (just enough to orient)

- W5 is the clean-slate successor to W4.1 (which lives at
  D:/assets/world 4/ as frozen reference).
- 47 system specs at docs/specs/ — each is a contract.
- Pillars (strict tiebreaker order):
  1. High visual quality / fidelity
  2. Performance (engine reserves 8 ms of 16.6 ms at high tier;
     see docs/specs/X_FRAME_BUDGET.md)
  3. Architecturally correct (forkable, no god-files)
  4. Time-to-ship NOT a constraint (no MVP culture)
- Read docs/SYSTEM_INVENTORY.md for the 5-tier map of all systems.
- Read docs/USAGE.md for how to run tests + open the project.
- Read docs/STATE.md for what currently exists.
- Pitfalls already known: docs/reference/pitfalls/pitfalls_INDEX.md
  (don't re-flag these unless you spot a NEW manifestation).

## Your specific scope

{{SCOPE}}

## What to check (lenses)

Apply these lenses to your scope:

{{LENSES — pick from:
  - Spec-vs-code adherence: does the implementation deliver what
    the spec promised?
  - Cross-system integration: do the wires to other systems work?
    (Tier 0 systems all integrate via /root/X autoloads + lazy
    lookup; integration tests live at engine/tests/integration/)
  - Test coverage gaps: which behaviors are NOT tested? Edge cases?
    Error paths? Race conditions? Empty/zero/large inputs?
  - Performance claims: did the spec promise perf bounds? Are they
    measured anywhere?
  - Audit fix verification: prior audits documented in
    docs/AUDIT_FINDINGS.md, SELF_AUDIT_FINDINGS.md,
    SELF_AUDIT_PHASE_2_FINDINGS.md — verify those fixes actually
    landed correctly.
  - Pitfall recurrence: check if any new code reproduces a known
    pitfall (meta-1 builtin shadowing, meta-2 headless/RD, meta-3
    dict iteration during erase).
}}

## What to return

A written assessment in this structure:

```markdown
# Review: {{SCOPE}}

## Top-line (one paragraph)

Is the scope in a healthy state? Highest-priority concern? One
genuinely-strong thing? Would you ship this?

## Critical findings (must address)

Format each as:
**[severity-id]: [one-line title]**
- File(s): [paths with line numbers if applicable]
- What's wrong: [concrete description]
- Why it matters: [downstream impact]
- Recommended fix: [specific change, not "improve X"]

## Significant findings

Same format. Worth addressing but not blocking.

## Minor findings / polish

Same format. Defer if needed.

## What the scope got right

Honest highlights worth preserving. Not flattery — specific things
that work well + why.

## What you could not assess

Things outside your scope or requiring info you don't have. Flag
these so the parent agent knows where blind spots are.
```

## Hard rules

1. **READ ONLY**: no Write, no Edit, no Bash commands that mutate
   state (git operations, package installs, file creation,
   filesystem changes). Read, Grep, Glob, WebFetch, WebSearch are
   fine.
2. **Cite evidence**: every finding names a specific file + line
   number (or test name or commit SHA). No vague "this code is
   bad" claims.
3. **Honest, not polite**: the parent agent asked for review
   because internal review is biased. Don't hedge. Don't soften
   "this is wrong" into "this could be improved."
4. **Acknowledge your own bias**: if you find yourself agreeing
   with the parent's framing too easily, flag it. Independent
   perspective is the value.
5. **No work proposals beyond fixes**: don't suggest new features
   or refactors. The parent owns scope decisions.
6. **Cap response under {{WORD_CAP — typical 1500 words}}**.
   Findings should be terse + actionable.

## Severity scale

- **C**: critical — would cause real harm if shipped (incorrect
  output, crash, security issue, broken contract). Block the merge.
- **S**: significant — worth addressing this revision pass.
- **M**: minor — polish; can defer.

Use {{ID_PREFIX — e.g. "SUB-A"}}-C1, -S1, -M1 etc. so findings are
addressable when the parent acts on them.

## Start now

Begin by reading {{ENTRY_POINT_FILES}}. Then proceed through the
lenses + scope. Write findings as you go; don't pre-plan. Return
the structured assessment as your final message.
```

## Example invocations

### Single-agent: review a freshly-shipped system

```
Agent({
  description: "Review JobScheduler impl vs spec 07",
  subagent_type: "general-purpose",  # or claude
  prompt: <above template with:
    SCOPE = "engine/scripts/core/JobScheduler.gd + engine/tests/unit/test_job_system.gd against docs/specs/07_JOB_SYSTEM.md"
    LENSES = "Spec-vs-code adherence + Test coverage gaps + Pitfall recurrence (especially meta-3 iteration during erase)"
    ID_PREFIX = "JS-REV"
    WORD_CAP = "1500 words"
    ENTRY_POINT_FILES = "docs/specs/07_JOB_SYSTEM.md (the contract), engine/scripts/core/JobScheduler.gd (the impl), engine/tests/unit/test_job_system.gd (the tests)"
  >
})
```

### Multi-agent parallel: 3 lenses on one artifact

Dispatch in ONE message with 3 Agent tool calls so they run
concurrently:

```
Agent #1: SCOPE = "spec 21 TERRAIN_RENDERER + the renderer modules"
  LENSES = "Spec-vs-code adherence"
  ID_PREFIX = "TR-SPEC"

Agent #2: same SCOPE
  LENSES = "Performance claims + frame budget arithmetic"
  ID_PREFIX = "TR-PERF"

Agent #3: same SCOPE
  LENSES = "Cross-system integration (StreamingBudget, JobScheduler,
    AssetStream, ChangeBroadcast wires)"
  ID_PREFIX = "TR-INTEG"
```

Parent agent then merges the 3 written assessments into a single
findings doc + acts on the union of issues. No shared write state
between the 3.

### Multi-agent parallel: different scopes simultaneously

Each agent reviews a different system. Useful before a big phase
close.

```
Agent #1: SCOPE = "Tier 0 specs 07-12"
Agent #2: SCOPE = "Tier 0 specs 13-18"
Agent #3: SCOPE = "Tier 1 specs 19-25"
Agent #4: SCOPE = "Tier 2 specs 35-41"
```

Each returns findings; parent assembles into a phase-audit doc.

## When parent re-engages

After all agents return:

1. Read each agent's response in full
2. Merge findings into one doc (deduplicate; agent A and B may flag
   the same thing differently)
3. Apply the same severity tiering across all (C/S/M)
4. Decide which to action this pass vs defer (use the
   audit-fix-pass pattern from SELF_AUDIT_PHASE_2_FINDINGS)
5. Implement fixes serially (parent does ALL writes; subagents
   stay read-only)

## Anti-patterns

- ❌ Dispatching a subagent to "fix the bugs it finds" — that's
  build work, not review work. Use feature-dev for fixes.
- ❌ Dispatching subagents for trivially-small reviews (< 100 lines
  of code). The orchestration overhead exceeds the benefit.
- ❌ Letting subagents communicate with each other. They don't have
  a shared bus; if work needs coordination it isn't independent.
- ❌ Skipping the "acknowledge bias" hard rule. Self-audit agents
  that agree too readily produce the same blind spots as the
  parent.

## Doc cap status

This file: ~210 lines. Under the 350 workflow doc cap.

## See also

- docs/SELF_AUDIT_PHASE_2_FINDINGS.md — example of a thorough audit
  doc structure (resolution table at bottom is the model)
- docs/AUDIT_PROMPT.md — the older outside-audit prompt for the
  spec layer; this workflow is the in-session subagent analog
- superpowers:dispatching-parallel-agents skill — the broader
  pattern; this prompt is the review-specific specialization
