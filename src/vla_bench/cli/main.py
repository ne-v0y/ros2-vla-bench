import typer
from rich import print

from vla_bench.core.config import load_config


app = typer.Typer(
    help="Pluggable VLA robotics benchmark runner",
)


@app.command("list")
def list_plugins():
    print("[bold]VLA Bench[/bold]")
    print("Model and benchmark adapters are installed separately.")


@app.command()
def validate(config: str):
    cfg = load_config(config)

    missing = [
        key
        for key in ("model", "benchmark")
        if key not in cfg
    ]

    if missing:
        raise typer.BadParameter(
            f"Missing config keys: {missing}"
        )

    print("[green]Config is structurally valid.[/green]")


if __name__ == "__main__":
    app()
