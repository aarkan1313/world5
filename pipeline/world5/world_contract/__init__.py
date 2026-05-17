"""W5 world contract — preflight validators for world bundles.

Per spec 14. Each system spec declares its world-contract requirements
in its Quality bar; this module collects + runs them.

Phase 2.11 ships the host + 3 cross-cutting preflight checks
(godot_root_check, doc_health, logging_lint). Per-system checks land
when each Tier 1+ system ships content.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from world5.log import log
from world5.world_contract._types import Issue, Severity

SYSTEM_NAME = "world_contract"

REPO_ROOT = Path(__file__).resolve().parents[3]


@dataclass
class ContractResult:
    passed: bool
    issues: list[Issue]

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == Severity.ERROR]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.severity == Severity.WARNING]

    def to_dict(self) -> dict:
        return {
            "passed": self.passed,
            "error_count": len(self.errors),
            "warning_count": len(self.warnings),
            "issues": [
                {
                    "severity": i.severity.value,
                    "code": i.code,
                    "message": i.message,
                    "path": i.path,
                    **i.details,
                }
                for i in self.issues
            ],
        }


# Check function signature: (repo_root, world_path, tier) → list[Issue]
CheckFn = Callable[[Path, Path | None, str], list[Issue]]

# Registry: code-prefix → check function
_CHECKS: dict[str, CheckFn] = {}


def register_check(prefix: str, fn: CheckFn) -> None:
    """Register a check. Each function returns Issues with codes
    namespaced under `prefix.*` (e.g. 'allowlist.disallowed_dir')."""
    _CHECKS[prefix] = fn


def get_registered() -> dict[str, CheckFn]:
    return dict(_CHECKS)


def validate(
    world_path: Path | None = None,
    tier: str = "high",
    strict: bool = False,
    repo_root: Path | None = None,
) -> ContractResult:
    """Run all registered preflight checks. Returns ContractResult.

    world_path: optional; many checks (allowlist, doc_health, lint)
        operate on the repo, not a specific world bundle. Pass None
        for repo-only checks.
    strict: if True, warnings also fail the result.
    """
    root = repo_root or REPO_ROOT
    all_issues: list[Issue] = []
    for prefix, check_fn in _CHECKS.items():
        try:
            issues = check_fn(root, world_path, tier)
            all_issues.extend(issues)
        except Exception as e:
            all_issues.append(Issue(
                severity=Severity.ERROR,
                code=f"{prefix}.check_crashed",
                message=f"Check '{prefix}' raised: {e}",
            ))
    fail_severities = {Severity.ERROR}
    if strict:
        fail_severities.add(Severity.WARNING)
    passed = not any(i.severity in fail_severities for i in all_issues)
    return ContractResult(passed=passed, issues=all_issues)


# Register the built-in checks at import time
from world5.world_contract import godot_root_check, doc_health, logging_lint  # noqa: E402

register_check("allowlist", godot_root_check.run)
register_check("doc_health", doc_health.run)
register_check("logging_lint", logging_lint.run)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="world5.world_contract",
        description="W5 preflight validator (spec 14)."
    )
    parser.add_argument("--world", type=Path, default=None,
                        help="World bundle path (optional; many checks are repo-wide)")
    parser.add_argument("--tier", default="high",
                        help="Quality tier for tier-aware checks")
    parser.add_argument("--strict", action="store_true",
                        help="Fail on warnings too, not just errors")
    parser.add_argument("--json", action="store_true",
                        help="JSON output for LLM consumption")
    args = parser.parse_args(argv)

    result = validate(world_path=args.world, tier=args.tier, strict=args.strict)
    if args.json:
        print(json.dumps(result.to_dict(), indent=2))
    else:
        status = "PASS" if result.passed else "FAIL"
        print(f"W5 world_contract: {status}  "
              f"({len(result.errors)} errors, {len(result.warnings)} warnings)")
        for issue in result.issues:
            marker = {"error": "ERR", "warning": "warn", "info": "info"}[issue.severity.value]
            path_str = f" [{issue.path}]" if issue.path else ""
            print(f"  [{marker:>4}] {issue.code}{path_str}: {issue.message}")
    return 0 if result.passed else (2 if any(i.severity == Severity.WARNING for i in result.issues) and args.strict else 1)


if __name__ == "__main__":
    sys.exit(main())
