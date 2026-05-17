"""Shared types for world_contract checks. Avoids circular imports."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Severity(str, Enum):
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"


@dataclass
class Issue:
    severity: Severity
    code: str
    message: str
    path: str | None = None
    details: dict = field(default_factory=dict)
