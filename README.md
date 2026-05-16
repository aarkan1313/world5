# W5 — World 5

A Godot 4.5 + Python world-generation engine, shipped as a Godot
plugin, consumable by external game projects.

Clean-slate successor to W4.1 (at `../world 4/`, frozen reference).

## Status

**Phase 1 (spec layer) complete + audited + fixed.** Phase 0 (repo
setup) is the next sprint. No engine code exists yet — only specs.

See [docs/STATE.md](docs/STATE.md) for current; [docs/ROADMAP.md](docs/ROADMAP.md)
for what's next.

## Pillars (strict tiebreaker order)

1. High visual quality / fidelity
2. Performance + optimization (engine reserves 8 ms of 16.6 ms p99 on
   RTX 3060/4060; consumer game gets the other 8.6 ms)
3. Architecturally correct
4. Time-to-ship NOT a constraint

## Layout (post-Phase-0)

```
world 5/
├── engine/         # Godot addon (plugin.cfg + scripts/ + scenes/ + ...)
├── demo/           # Consumer Godot project that uses the addon
├── pipeline/       # Python pipeline (engine-agnostic content tools)
├── tests/          # pytest top-level
├── tools/          # one-off scripts
└── docs/           # all documentation (this is where to read)
```

## Where to start reading

- [docs/README.md](docs/README.md) — docs front door
- [docs/SYSTEM_INVENTORY.md](docs/SYSTEM_INVENTORY.md) — all systems mapped by tier
- [docs/specs/](docs/specs/) — 47 system specs
- [docs/ROADMAP.md](docs/ROADMAP.md) — phase-level plan

## Success metric

W5 is "done" when it is a **usable, exportable, swappable world
generator forkable into 3+ independent game projects.** First consumer
is a 2.5D wizard game; engine itself is game-agnostic.

## License

TBD — picked before v0.1.0 release. Placeholder.
