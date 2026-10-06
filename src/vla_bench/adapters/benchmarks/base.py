from abc import ABC, abstractmethod
from collections.abc import Iterable

from vla_bench.core.types import Action, EpisodeResult, Observation


class BenchmarkAdapter(ABC):
    @abstractmethod
    def setup(self) -> None:
        ...

    @abstractmethod
    def tasks(self) -> Iterable[dict]:
        ...

    @abstractmethod
    def reset(
        self,
        task: dict,
    ) -> tuple[Observation, str]:
        ...

    @abstractmethod
    def step(
        self,
        action: Action,
    ) -> tuple[Observation, bool, dict]:
        ...

    @abstractmethod
    def result(self) -> EpisodeResult:
        ...

    def close(self) -> None:
        ...
