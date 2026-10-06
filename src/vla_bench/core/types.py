from dataclasses import dataclass, field
from typing import Any


@dataclass
class Observation:
    data: dict[str, Any]


@dataclass
class Action:
    data: Any


@dataclass
class EpisodeResult:
    success: bool
    reward: float | None = None
    steps: int = 0
    metrics: dict[str, Any] = field(default_factory=dict)
