MODEL_REGISTRY: dict[str, type] = {}
BENCHMARK_REGISTRY: dict[str, type] = {}
SIMULATOR_REGISTRY: dict[str, type] = {}


def register_model(name: str):
    def inner(cls):
        MODEL_REGISTRY[name] = cls
        return cls

    return inner


def register_benchmark(name: str):
    def inner(cls):
        BENCHMARK_REGISTRY[name] = cls
        return cls

    return inner


def register_simulator(name: str):
    def inner(cls):
        SIMULATOR_REGISTRY[name] = cls
        return cls

    return inner
