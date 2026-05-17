"""Tests for world_contract preflight system.

Per spec 14 + Phase 2.11.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from world5.world_contract import (
    ContractResult,
    Issue,
    Severity,
    validate,
)
from world5.world_contract._types import Issue as TypedIssue
from world5.world_contract import godot_root_check, doc_health, logging_lint


def _make_min_repo(tmp_path: Path) -> Path:
    """Create a minimal valid W5 repo structure for testing."""
    (tmp_path / "engine" / "scripts" / "core").mkdir(parents=True)
    (tmp_path / "engine" / "scripts" / "core" / "Log.gd").write_text(
        "# Log wrapper\nfunc info(): push_warning('ok')\n", encoding="utf-8")
    (tmp_path / "engine" / "scenes").mkdir()
    (tmp_path / "engine" / "tests" / "unit").mkdir(parents=True)
    (tmp_path / "engine" / "plugin.cfg").write_text("[plugin]\nname=\"X\"\n",
                                                     encoding="utf-8")
    (tmp_path / "demo").mkdir()
    (tmp_path / "demo" / "project.godot").write_text("config_version=5\n",
                                                       encoding="utf-8")
    (tmp_path / "demo" / "scenes").mkdir()
    return tmp_path


# --- godot_root_check ---

def test_allowlist_passes_on_valid_repo(tmp_path):
    repo = _make_min_repo(tmp_path)
    issues = godot_root_check.run(repo, None, "high")
    errors = [i for i in issues if i.severity == Severity.ERROR]
    assert not errors


def test_allowlist_flags_disallowed_engine_dir(tmp_path):
    repo = _make_min_repo(tmp_path)
    (repo / "engine" / "candidates").mkdir()  # the trap
    issues = godot_root_check.run(repo, None, "high")
    codes = [i.code for i in issues]
    assert "allowlist.engine_disallowed_dir" in codes


def test_allowlist_flags_disallowed_demo_dir(tmp_path):
    repo = _make_min_repo(tmp_path)
    (repo / "demo" / "scratch").mkdir()
    issues = godot_root_check.run(repo, None, "high")
    codes = [i.code for i in issues]
    assert "allowlist.demo_disallowed_dir" in codes


def test_allowlist_skips_hidden_dirs(tmp_path):
    repo = _make_min_repo(tmp_path)
    (repo / "engine" / ".godot").mkdir()  # hidden; should be ignored
    issues = godot_root_check.run(repo, None, "high")
    assert all(".godot" not in (i.path or "") for i in issues)


def test_allowlist_example_size_cap(tmp_path):
    repo = _make_min_repo(tmp_path)
    examples = repo / "engine" / "examples"
    examples.mkdir()
    big_ex = examples / "big_one"
    big_ex.mkdir()
    # Write a 25 MB file (over 20 MB per-dir cap)
    (big_ex / "huge.bin").write_bytes(b"\0" * (25 * 1024 * 1024))
    issues = godot_root_check.run(repo, None, "high")
    codes = [i.code for i in issues]
    assert "allowlist.example_too_large" in codes


# --- doc_health ---

def test_doc_health_no_docs_no_issues(tmp_path):
    # docs/ doesn't exist → no issues, no crash
    issues = doc_health.run(tmp_path, None, "high")
    assert issues == []


def test_doc_health_flags_over_cap(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    # README over 200 line cap
    (docs / "README.md").write_text("\n" * 250, encoding="utf-8")
    issues = doc_health.run(tmp_path, None, "high")
    codes = [i.code for i in issues]
    assert "doc_health.top_level_over_cap" in codes


def test_doc_health_under_cap_passes(tmp_path):
    docs = tmp_path / "docs"
    docs.mkdir()
    (docs / "README.md").write_text("# small\n" * 10, encoding="utf-8")
    issues = doc_health.run(tmp_path, None, "high")
    assert not any(i.code.startswith("doc_health.top_level") for i in issues)


# --- logging_lint ---

def test_lint_flags_direct_print(tmp_path):
    repo = _make_min_repo(tmp_path)
    (repo / "engine" / "scripts" / "terrain").mkdir()
    (repo / "engine" / "scripts" / "terrain" / "bad.gd").write_text(
        "func do_thing():\n\tprint('hi')\n", encoding="utf-8")
    issues = logging_lint.run(repo, None, "high")
    codes = [i.code for i in issues]
    assert "logging_lint.direct_call" in codes


def test_lint_flags_push_error(tmp_path):
    repo = _make_min_repo(tmp_path)
    (repo / "engine" / "scripts" / "x" ).mkdir(parents=True)
    (repo / "engine" / "scripts" / "x" / "bad.gd").write_text(
        "func do():\n\tpush_error('oops')\n", encoding="utf-8")
    issues = logging_lint.run(repo, None, "high")
    assert any(i.code == "logging_lint.direct_call" for i in issues)


def test_lint_exempts_log_gd(tmp_path):
    repo = _make_min_repo(tmp_path)
    # Log.gd itself uses push_warning legally
    (repo / "engine" / "scripts" / "core" / "Log.gd").write_text(
        "func warn():\n\tpush_warning('w')\n", encoding="utf-8")
    issues = logging_lint.run(repo, None, "high")
    assert not any(i.path and "Log.gd" in i.path for i in issues)


def test_lint_respects_suppress_marker(tmp_path):
    repo = _make_min_repo(tmp_path)
    (repo / "engine" / "scripts" / "y").mkdir(parents=True)
    (repo / "engine" / "scripts" / "y" / "ok.gd").write_text(
        "func do():\n\tprint('test')  # LINT_OK reason\n", encoding="utf-8")
    issues = logging_lint.run(repo, None, "high")
    assert not any("ok.gd" in (i.path or "") for i in issues)


def test_lint_ignores_comments(tmp_path):
    repo = _make_min_repo(tmp_path)
    (repo / "engine" / "scripts" / "z").mkdir(parents=True)
    (repo / "engine" / "scripts" / "z" / "doc.gd").write_text(
        "# This function should NOT use print() directly\nfunc x(): pass\n",
        encoding="utf-8")
    issues = logging_lint.run(repo, None, "high")
    assert not any("doc.gd" in (i.path or "") for i in issues)


# --- top-level validate ---

def test_validate_returns_contract_result(tmp_path):
    """Smoke test of the top-level validate() entry point."""
    repo = _make_min_repo(tmp_path)
    result = validate(repo_root=repo)
    assert isinstance(result, ContractResult)
    assert isinstance(result.passed, bool)


def test_validate_real_repo_passes():
    """The actual W5 repo should pass preflight (we fixed the lint
    violations during Phase 2.11)."""
    result = validate()
    if not result.passed:
        for issue in result.errors:
            print(f"  [{issue.severity}] {issue.code}: {issue.message}")
    assert result.passed, "Real W5 repo should pass preflight"


def test_validate_strict_mode_fails_on_warnings(tmp_path):
    repo = _make_min_repo(tmp_path)
    # Add a warning (file in engine/ not in allowed-files list)
    (repo / "engine" / "stray_file.txt").write_text("x", encoding="utf-8")
    result_normal = validate(repo_root=repo, strict=False)
    result_strict = validate(repo_root=repo, strict=True)
    # Normal passes (only a warning); strict fails on warning
    if result_normal.warnings:
        assert result_normal.passed
        assert not result_strict.passed
