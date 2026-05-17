"""Tests for world5.setup CLI (spec 18 + Phase 2.12)."""

from __future__ import annotations

from pathlib import Path

import pytest

from world5.setup import install_demo, verify_install


def _make_min_engine(tmp_path: Path) -> Path:
    """Create minimal engine/ structure."""
    engine = tmp_path / "engine"
    (engine / "scripts" / "core").mkdir(parents=True)
    (engine / "plugin.cfg").write_text(
        '[plugin]\nname="World5"\nversion="0.0.1"\n', encoding="utf-8")
    for f in ["Log.gd", "World5.gd", "QualityTiers.gd", "JobScheduler.gd",
              "AssetStream.gd"]:
        (engine / "scripts" / "core" / f).write_text("# stub\n",
                                                       encoding="utf-8")
    return engine


# --- install_demo ---

def test_install_demo_creates_link(tmp_path):
    _make_min_engine(tmp_path)
    code = install_demo(repo_root=tmp_path)
    assert code == 0
    link = tmp_path / "demo" / "addons" / "world5"
    assert link.exists()


def test_install_demo_idempotent(tmp_path):
    _make_min_engine(tmp_path)
    assert install_demo(repo_root=tmp_path) == 0
    # Second call should succeed (already linked)
    assert install_demo(repo_root=tmp_path) == 0


def test_install_demo_missing_engine_fails(tmp_path):
    # No engine/ dir
    code = install_demo(repo_root=tmp_path)
    assert code != 0


# --- verify_install ---

def test_verify_install_missing_consumer_fails(tmp_path):
    code = verify_install(tmp_path / "does_not_exist")
    assert code != 0


def test_verify_install_missing_addon_fails(tmp_path):
    # Consumer exists but no addons/world5/
    (tmp_path / "consumer").mkdir()
    code = verify_install(tmp_path / "consumer")
    assert code != 0


def test_verify_install_complete_addon_passes(tmp_path):
    # Consumer with full addons/world5/ structure
    consumer = tmp_path / "consumer"
    addon = consumer / "addons" / "world5"
    (addon / "scripts" / "core").mkdir(parents=True)
    (addon / "plugin.cfg").write_text(
        '[plugin]\nname="World5"\nversion="0.0.1"\n', encoding="utf-8")
    for f in ["Log.gd", "World5.gd", "QualityTiers.gd", "JobScheduler.gd",
              "AssetStream.gd"]:
        (addon / "scripts" / "core" / f).write_text("# stub\n",
                                                      encoding="utf-8")
    code = verify_install(consumer)
    assert code == 0


def test_verify_install_missing_core_script_fails(tmp_path):
    consumer = tmp_path / "consumer"
    addon = consumer / "addons" / "world5"
    (addon / "scripts" / "core").mkdir(parents=True)
    (addon / "plugin.cfg").write_text(
        '[plugin]\nversion="0.0.1"\n', encoding="utf-8")
    # Only Log.gd; missing others
    (addon / "scripts" / "core" / "Log.gd").write_text("", encoding="utf-8")
    code = verify_install(consumer)
    assert code != 0
