from abc import ABC, abstractmethod

from vla_bench.core.types import Action, Observation


class ModelAdapter(ABC):
    @abstractmethod
    def load(self) -> None:
        ...

    @abstractmethod
    def reset(self, task: dict) -> None:
        ...

    @abstractmethod
    def act(
        self,
        observation: Observation,
        instruction: str,
    ) -> Action:
        ...

    def close(self) -> None:
        ...
