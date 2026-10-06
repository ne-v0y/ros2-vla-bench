from abc import ABC, abstractmethod


class SimulatorAdapter(ABC):
    @abstractmethod
    def start(self) -> None:
        ...

    @abstractmethod
    def stop(self) -> None:
        ...
