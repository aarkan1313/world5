"""Tests for world5.version semver helpers.

Per spec 17.
"""

from __future__ import annotations

import pytest

from world5.version import (
    WORLD5_VERSION,
    is_compatible,
    migration_path,
    needs_migration,
    parse,
)


def test_version_loaded_from_plugin_cfg():
    """WORLD5_VERSION reads from plugin.cfg at import time."""
    # Phase 0 ships 0.0.1 per engine/plugin.cfg
    assert WORLD5_VERSION == "0.0.1"


def test_parse_valid_semver():
    assert parse("1.2.3") == (1, 2, 3)
    assert parse("0.1.0") == (0, 1, 0)
    assert parse("10.20.30") == (10, 20, 30)


def test_parse_strips_prerelease():
    assert parse("0.1.0-beta.1") == (0, 1, 0)
    assert parse("1.0.0-rc.5") == (1, 0, 0)


def test_parse_invalid_returns_zero():
    assert parse("not.a.version") == (0, 0, 0)
    assert parse("1.2") == (0, 0, 0)
    assert parse("") == (0, 0, 0)


def test_is_compatible_same_version():
    assert is_compatible("0.0.1", "0.0.1") is True


def test_is_compatible_post_1_0_same_major():
    """Post-1.0: MINOR + PATCH differences are compatible."""
    assert is_compatible("1.0.0", "1.5.3") is True
    assert is_compatible("1.5.3", "1.0.0") is True


def test_is_compatible_pre_1_0_minor_breaks():
    """Pre-1.0: MINOR differences break compat per spec 17."""
    assert is_compatible("0.1.0", "0.2.0") is False
    assert is_compatible("0.1.5", "0.1.7") is True  # PATCH OK


def test_is_compatible_major_diff_breaks():
    assert is_compatible("1.0.0", "2.0.0") is False
    assert is_compatible("2.5.0", "1.5.0") is False


def test_needs_migration_inverse_of_compat():
    assert needs_migration("0.0.1", "0.0.1") is False
    assert needs_migration("0.1.0", "0.2.0") is True
    assert needs_migration("1.0.0", "2.0.0") is True


def test_migration_path_same_returns_empty():
    assert migration_path("0.1.0", "0.1.0") == []


def test_migration_path_direct_stub():
    # Phase 2.2 stub returns [to_v] directly
    assert migration_path("0.1.0", "0.4.0") == ["0.4.0"]
