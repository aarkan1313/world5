"""Spec 04 allowlist preflight: verifies engine/ + demo/ contents
match the allowed directory list.

Per spec 04: prevents the W4.1 candidates/ trap (pipeline scratch
accidentally placed inside Godot project root → 9 GB scan on every
import).
"""

from __future__ import annotations

from pathlib import Path

from world5.world_contract._types import Issue, Severity


# engine/ allowlist (post-audit C7 + M11)
ENGINE_ALLOWED_DIRS = {
    "scripts", "scenes", "shaders", "resources", "tests", "examples",
    "addons", "decoration_meshes", "foliage_meshes", "cave_meshes",
    "worlds",
}
ENGINE_ALLOWED_FILES = {
    "plugin.cfg", "plugin.gd", "plugin.gd.uid",
    "README.md", "LICENSE", "CHANGELOG.md",
    "RELEASE_NOTES.md", "INSTALL.md", "MIGRATION.md",
}

# demo/ allowlist (per spec 04)
DEMO_ALLOWED_DIRS = {
    "addons", "scenes", "worlds", "scripts", "resources",
}
DEMO_ALLOWED_FILES = {
    "project.godot", "README.md", "LICENSE", "icon.svg", "icon.svg.import",
}

# Size caps (post-audit C7)
EXAMPLES_PER_DIR_CAP_MB = 20
EXAMPLES_AGGREGATE_CAP_MB = 100


def _dir_size_mb(path: Path) -> float:
    total = 0
    for p in path.rglob("*"):
        if p.is_file():
            total += p.stat().st_size
    return total / (1024 * 1024)


def run(repo_root: Path, world_path: Path | None, tier: str) -> list[Issue]:
    issues: list[Issue] = []

    # --- engine/ ---
    engine = repo_root / "engine"
    if engine.exists():
        for entry in engine.iterdir():
            name = entry.name
            # Skip hidden files (.gitkeep, .godot, etc.) — those are
            # tooling not user-content
            if name.startswith("."):
                continue
            if entry.is_dir():
                if name not in ENGINE_ALLOWED_DIRS:
                    issues.append(Issue(
                        severity=Severity.ERROR,
                        code="allowlist.engine_disallowed_dir",
                        message=f"engine/{name}/ is not in spec 04 allowlist",
                        path=str(entry.relative_to(repo_root)),
                        details={
                            "suggestion": f"Move to pipeline/{name}/ or one of: "
                                          f"{sorted(ENGINE_ALLOWED_DIRS)}"
                        },
                    ))
            elif entry.is_file():
                if name not in ENGINE_ALLOWED_FILES:
                    issues.append(Issue(
                        severity=Severity.WARNING,
                        code="allowlist.engine_disallowed_file",
                        message=f"engine/{name} is not in spec 04 allowlist",
                        path=str(entry.relative_to(repo_root)),
                    ))

    # --- demo/ ---
    demo = repo_root / "demo"
    if demo.exists():
        for entry in demo.iterdir():
            name = entry.name
            if name.startswith("."):
                continue
            if entry.is_dir():
                if name not in DEMO_ALLOWED_DIRS:
                    issues.append(Issue(
                        severity=Severity.ERROR,
                        code="allowlist.demo_disallowed_dir",
                        message=f"demo/{name}/ is not in spec 04 allowlist",
                        path=str(entry.relative_to(repo_root)),
                    ))
            elif entry.is_file():
                if name not in DEMO_ALLOWED_FILES:
                    issues.append(Issue(
                        severity=Severity.WARNING,
                        code="allowlist.demo_disallowed_file",
                        message=f"demo/{name} is not in spec 04 allowlist",
                        path=str(entry.relative_to(repo_root)),
                    ))

    # --- engine/examples/ size caps ---
    examples = engine / "examples"
    if examples.exists():
        aggregate_mb = 0.0
        for ex_dir in examples.iterdir():
            if not ex_dir.is_dir():
                continue
            size_mb = _dir_size_mb(ex_dir)
            aggregate_mb += size_mb
            if size_mb > EXAMPLES_PER_DIR_CAP_MB:
                issues.append(Issue(
                    severity=Severity.ERROR,
                    code="allowlist.example_too_large",
                    message=f"engine/examples/{ex_dir.name}/ is {size_mb:.1f} MB "
                            f"(cap: {EXAMPLES_PER_DIR_CAP_MB} MB)",
                    path=str(ex_dir.relative_to(repo_root)),
                ))
        if aggregate_mb > EXAMPLES_AGGREGATE_CAP_MB:
            issues.append(Issue(
                severity=Severity.ERROR,
                code="allowlist.examples_aggregate_too_large",
                message=f"engine/examples/ aggregate is {aggregate_mb:.1f} MB "
                        f"(cap: {EXAMPLES_AGGREGATE_CAP_MB} MB)",
                path="engine/examples/",
            ))

    return issues
