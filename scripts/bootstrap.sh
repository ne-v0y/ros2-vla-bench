#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"

VENV="$ROOT/.venv"
PYTHON="$VENV/bin/python"

if [[ ! -x "$PYTHON" ]]; then
  echo "Creating Python virtual environment..."
  rm -rf "$VENV"
  python3 -m venv "$VENV"
fi

echo "Using Python:"
"$PYTHON" -c 'import sys; print(sys.executable)'

"$PYTHON" -m pip install --upgrade pip
"$PYTHON" -m pip install -e .

mkdir -p results
touch results/.gitkeep

echo
echo "Platform setup complete."
echo "Activate with:"
echo "  source $ROOT/.venv/bin/activate"
echo
echo "ROS / Gazebo setup:"
echo "  $ROOT/scripts/ros.sh setup"