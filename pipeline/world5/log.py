"""W5 logging — Python mirror of engine/scripts/core/Log.gd.

Per spec 16. 5 levels, structured + JSON output, per-system verbose.
Output format matches GDScript side bit-for-bit so log streams can be
unified across pipeline + engine.

Usage:
    from world5.log import log

    log.info("texture", "Pipeline complete", duration_s=42.3, prompts=20)
    log.error("decoration", "Bake failed", chunk=(2, 3), error=str(e))
"""

from __future__ import annotations

import json as _json
import sys
import time
from enum import IntEnum
from pathlib import Path

_T0_MS = int(time.monotonic() * 1000)


class Level(IntEnum):
    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3
    FATAL = 4


_LEVEL_NAMES = ["DEBUG", "INFO ", "WARN ", "ERROR", "FATAL"]
_SYSTEM_NAME_WIDTH = 15


class _LogConfig:
    """Module-level configuration. Mutable; thread-safety is per-call."""

    min_level: Level = Level.INFO
    format: str = "human"
    output: str = "stdout"
    verbose_systems: dict[str, bool] = {}
    _file_handle = None


def _ticks_ms() -> int:
    """Return ms since process start (mirrors Time.get_ticks_msec)."""
    return int(time.monotonic() * 1000) - _T0_MS


def _should_log(level: Level, system: str) -> bool:
    if level >= _LogConfig.min_level:
        return True
    if level == Level.DEBUG and _LogConfig.verbose_systems.get(system, False):
        return True
    return False


def _format_human(level: Level, system: str, message: str, kv: dict) -> str:
    ts = _ticks_ms()
    system_padded = system[:_SYSTEM_NAME_WIDTH].ljust(_SYSTEM_NAME_WIDTH)
    kv_str = ""
    if kv:
        parts = [f"{k}={v}" for k, v in kv.items()]
        kv_str = "  " + " ".join(parts)
    return f"[{_LEVEL_NAMES[level]}] [{system_padded}] [{ts:6d}] {message}{kv_str}"


def _format_json(level: Level, system: str, message: str, kv: dict) -> str:
    obj: dict = {
        "level": _LEVEL_NAMES[level].strip(),
        "system": system,
        "ts_ms": _ticks_ms(),
        "msg": message,
    }
    obj.update(kv)
    return _json.dumps(obj, default=str)


def _format_compact(level: Level, system: str, message: str, kv: dict) -> str:
    kv_str = ""
    if kv:
        parts = [f"{k}={v}" for k, v in kv.items()]
        kv_str = " " + " ".join(parts)
    return f"{_LEVEL_NAMES[level].strip()} {system} {message}{kv_str}"


def _emit(level: Level, system: str, message: str, kv: dict) -> None:
    if _LogConfig.format == "json":
        line = _format_json(level, system, message, kv)
    elif _LogConfig.format == "compact":
        line = _format_compact(level, system, message, kv)
    else:
        line = _format_human(level, system, message, kv)

    if _LogConfig.output in ("stdout", "both"):
        # Stderr for WARN+ so log aggregators can split; stdout for INFO/DEBUG
        stream = sys.stderr if level >= Level.WARN else sys.stdout
        print(line, file=stream)
    if _LogConfig._file_handle is not None:
        _LogConfig._file_handle.write(line + "\n")
        _LogConfig._file_handle.flush()


class _LogFacade:
    """Bound-method facade so `log.info(...)` reads naturally."""

    def debug(self, system: str, message: str, **kv) -> None:
        if _should_log(Level.DEBUG, system):
            _emit(Level.DEBUG, system, message, kv)

    def info(self, system: str, message: str, **kv) -> None:
        if _should_log(Level.INFO, system):
            _emit(Level.INFO, system, message, kv)

    def warn(self, system: str, message: str, **kv) -> None:
        if _should_log(Level.WARN, system):
            _emit(Level.WARN, system, message, kv)

    def error(self, system: str, message: str, **kv) -> None:
        if _should_log(Level.ERROR, system):
            _emit(Level.ERROR, system, message, kv)

    def fatal(self, system: str, message: str, **kv) -> None:
        _emit(Level.FATAL, system, message, kv)

    def is_verbose(self, system: str) -> bool:
        return _LogConfig.verbose_systems.get(system, False)

    def set_verbose(self, system: str, enabled: bool) -> None:
        _LogConfig.verbose_systems[system] = enabled

    def set_level(self, min_level: Level) -> None:
        _LogConfig.min_level = min_level

    def set_format(self, format: str) -> None:
        assert format in ("human", "json", "compact"), "format must be human/json/compact"
        _LogConfig.format = format

    def set_output(self, target: str) -> None:
        if _LogConfig._file_handle is not None:
            _LogConfig._file_handle.close()
            _LogConfig._file_handle = None
        _LogConfig.output = target
        if target.startswith("file:") or target == "both":
            path = target[5:] if target.startswith("file:") else "world5.log"
            _LogConfig._file_handle = Path(path).open("a", encoding="utf-8")


log = _LogFacade()
