#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip install --upgrade pip
python -m pip install -e .

mkdir -p results
touch results/.gitkeep

echo
echo "Platform setup complete."
echo "Activate with:"
echo "  source $ROOT/.venv/bin/activate"
echo
echo "ROS / Gazebo setup:"
echo "  $ROOT/scripts/ros.sh setup"
