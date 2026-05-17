"""Tests for world5.log Python logger.

Per spec 06 + spec 16.
"""

from __future__ import annotations

import io
import json
import sys

import pytest

from world5.log import _LogConfig, _format_human, _format_json, Level, log


@pytest.fixture(autouse=True)
def _reset_log_config():
    """Reset log config to defaults between tests."""
    _LogConfig.min_level = Level.INFO
    _LogConfig.format = "human"
    _LogConfig.output = "stdout"
    _LogConfig.verbose_systems = {}
    _LogConfig._file_handle = None
    yield


def test_human_format_shape():
    line = _format_human(Level.INFO, "terrain", "Ring 3 ready", {"duration_ms": 87})
    # Pattern: [INFO ] [terrain        ] [   xxxx] Ring 3 ready  duration_ms=87
    assert line.startswith("[INFO ]")
    assert "[terrain        ]" in line  # 15-char left-padded
    assert "Ring 3 ready" in line
    assert "duration_ms=87" in line


def test_human_format_no_kv():
    line = _format_human(Level.WARN, "decoration", "Just a warning", {})
    assert line.startswith("[WARN ]")
    assert "Just a warning" in line
    assert "=" not in line.split("Just a warning")[1]


def test_json_format_valid():
    line = _format_json(Level.ERROR, "asset_stream", "Load failed", {"path": "x.glb"})
    obj = json.loads(line)
    assert obj["level"] == "ERROR"
    assert obj["system"] == "asset_stream"
    assert obj["msg"] == "Load failed"
    assert obj["path"] == "x.glb"
    assert isinstance(obj["ts_ms"], int)


def test_level_filter_blocks_below():
    captured = io.StringIO()
    sys.stdout = captured
    try:
        log.set_level(Level.WARN)
        log.info("test", "should not appear")
        log.warn("test", "should appear")
    finally:
        sys.stdout = sys.__stdout__
    # WARN goes to stderr per facade, so stdout should have only INFO (which was blocked)
    assert "should not appear" not in captured.getvalue()


def test_verbose_per_system():
    captured_out = io.StringIO()
    captured_err = io.StringIO()
    sys.stdout = captured_out
    sys.stderr = captured_err
    try:
        log.set_level(Level.INFO)
        log.set_verbose("terrain", True)
        log.debug("terrain", "verbose debug")
        log.debug("decoration", "not verbose debug")
    finally:
        sys.stdout = sys.__stdout__
        sys.stderr = sys.__stderr__
    assert "verbose debug" in captured_out.getvalue()
    assert "not verbose debug" not in captured_out.getvalue()


def test_format_setter_validates():
    with pytest.raises(AssertionError):
        log.set_format("invalid_format")


def test_facade_methods_exist():
    """All 5 level methods + config methods exist."""
    assert callable(log.debug)
    assert callable(log.info)
    assert callable(log.warn)
    assert callable(log.error)
    assert callable(log.fatal)
    assert callable(log.set_level)
    assert callable(log.set_format)
    assert callable(log.set_output)
    assert callable(log.set_verbose)
    assert callable(log.is_verbose)
