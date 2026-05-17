"""Spec 16 logging lint: forbids direct print / push_warning /
push_error calls outside Log.gd.

Per spec 16 + audit M11: every log call must go through Log.gd.
Direct calls bypass the format / level / output configuration.

Scans engine/scripts/ for forbidden calls. Allowed exceptions:
- engine/scripts/core/Log.gd itself
- Lines inside `if false` / `#` comment blocks (basic detection)
- Lines containing `# LINT_OK` suppression marker
"""

from __future__ import annotations

import re
from pathlib import Path

from world5.world_contract._types import Issue, Severity


# Forbidden patterns: `print(`, `push_warning(`, `push_error(`
# Only match at call position (avoid matching e.g. "print_msg" var names)
_FORBIDDEN = [
    (re.compile(r"\bprint\("), "print"),
    (re.compile(r"\bpush_warning\("), "push_warning"),
    (re.compile(r"\bpush_error\("), "push_error"),
    (re.compile(r"\bprint_rich\("), "print_rich"),
    (re.compile(r"\bprintt\("), "printt"),
    (re.compile(r"\bprints\("), "prints"),
]

# Files/dirs exempt from the lint
_EXEMPT_FILES = {
    "Log.gd",  # the wrapper itself
}
_EXEMPT_DIRS = {
    "addons",  # third-party (gut etc.) not subject to W5 conventions
    "tests",   # tests can use whatever (test output is its own thing)
    "examples", # examples may demo direct Godot APIs
}

_SUPPRESS_MARKER = "# LINT_OK"


def run(repo_root: Path, world_path: Path | None, tier: str) -> list[Issue]:
    issues: list[Issue] = []
    scripts = repo_root / "engine" / "scripts"
    if not scripts.exists():
        return issues

    for path in scripts.rglob("*.gd"):
        # Skip exempt dirs (anywhere in path)
        if any(part in _EXEMPT_DIRS for part in path.parts):
            continue
        if path.name in _EXEMPT_FILES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            # Strip everything from `#` onward EXCEPT detect LINT_OK first
            if _SUPPRESS_MARKER in line:
                continue
            stripped = line.split("#")[0]
            if not stripped.strip():
                continue
            for pattern, name in _FORBIDDEN:
                if pattern.search(stripped):
                    issues.append(Issue(
                        severity=Severity.ERROR,
                        code="logging_lint.direct_call",
                        message=f"direct `{name}` call outside Log.gd; "
                                f"use Log.{name.replace('push_', '')}() instead "
                                f"(suppress with '# LINT_OK' if intentional)",
                        path=str(path.relative_to(repo_root)),
                        details={"line": lineno, "text": line.strip()},
                    ))
                    break  # one issue per line
    return issues
