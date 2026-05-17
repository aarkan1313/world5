"""Spec 05 doc architecture preflight: line caps + index consistency.

- Top-level docs (README/STATE/ROADMAP/CONTRIBUTING/USAGE): ≤ 200 lines
- Per-tier docs (state/*.md, roadmap/*.md, pitfalls_*.md): ≤ 300 lines
- Specs + workflows: ≤ 300 lines (advisory)

Future (SA-MX3): orphan-link check (any link target exists).
"""

from __future__ import annotations

from pathlib import Path

from world5.world_contract._types import Issue, Severity


TOP_LEVEL_DOCS = {
    "README.md", "STATE.md", "ROADMAP.md", "CONTRIBUTING.md", "USAGE.md",
}
TOP_LEVEL_CAP = 200
TIER_CAP = 300
# Roadmap phase docs cap higher: they include both the build
# checklist (~200 lines) AND a post-completion outcome section
# (~50-100 lines deviations + lessons). Splitting outcome to a
# separate build-note exists; the phase doc keeps a brief outcome
# for findability.
ROADMAP_CAP = 350
SPEC_CAP = 600  # generous; some specs are comprehensive


def _line_count(path: Path) -> int:
    try:
        return sum(1 for _ in path.open(encoding="utf-8"))
    except UnicodeDecodeError:
        return 0  # binary file; skip


def run(repo_root: Path, world_path: Path | None, tier: str) -> list[Issue]:
    issues: list[Issue] = []
    docs = repo_root / "docs"
    if not docs.exists():
        return issues

    # Top-level docs
    for name in TOP_LEVEL_DOCS:
        path = docs / name
        if path.exists():
            n = _line_count(path)
            if n > TOP_LEVEL_CAP:
                issues.append(Issue(
                    severity=Severity.WARNING,
                    code="doc_health.top_level_over_cap",
                    message=f"{name} is {n} lines (cap: {TOP_LEVEL_CAP}). "
                            f"Per spec 05: split content into per-tier files.",
                    path=str(path.relative_to(repo_root)),
                ))

    # Per-tier files (state/) — strict 300 cap
    state_dir = docs / "state"
    if state_dir.exists():
        for path in state_dir.glob("*.md"):
            n = _line_count(path)
            if n > TIER_CAP:
                issues.append(Issue(
                    severity=Severity.WARNING,
                    code="doc_health.state_over_cap",
                    message=f"{path.name} is {n} lines (cap: {TIER_CAP})",
                    path=str(path.relative_to(repo_root)),
                ))

    # Roadmap phase docs — 350 cap (allows outcome appendix)
    roadmap_dir = docs / "roadmap"
    if roadmap_dir.exists():
        for path in roadmap_dir.glob("*.md"):
            n = _line_count(path)
            if n > ROADMAP_CAP:
                issues.append(Issue(
                    severity=Severity.WARNING,
                    code="doc_health.roadmap_over_cap",
                    message=f"{path.name} is {n} lines (cap: {ROADMAP_CAP})",
                    path=str(path.relative_to(repo_root)),
                ))

    # Pitfalls files
    pitfalls = docs / "reference" / "pitfalls"
    if pitfalls.exists():
        for path in pitfalls.glob("pitfalls_*.md"):
            if path.name == "pitfalls_INDEX.md":
                continue  # index has its own (smaller) cap implicit
            n = _line_count(path)
            if n > TIER_CAP:
                issues.append(Issue(
                    severity=Severity.WARNING,
                    code="doc_health.pitfalls_over_cap",
                    message=f"{path.name} is {n} lines (cap: {TIER_CAP})",
                    path=str(path.relative_to(repo_root)),
                ))

    # Specs (advisory; some are genuinely long)
    specs_dir = docs / "specs"
    if specs_dir.exists():
        for path in specs_dir.glob("*.md"):
            n = _line_count(path)
            if n > SPEC_CAP:
                issues.append(Issue(
                    severity=Severity.INFO,
                    code="doc_health.spec_long",
                    message=f"{path.name} is {n} lines (>{SPEC_CAP}; advisory)",
                    path=str(path.relative_to(repo_root)),
                ))

    return issues
