#!/usr/bin/env bash
# Open a Terminator window for the apartment scenario with six panes: sim,
# teleop, rviz, a vla-bench-ros container command (typed, not run) and two
# spare shells. ROS is sourced in every pane.
#
#   scripts/apartment.sh        open the window
#   scripts/apartment.sh stop   stop the sim, close the window, kill leftover Gazebo
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_DISTRO_EXPECTED="${ROS_DISTRO_EXPECTED:-jazzy}"
RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/vla-bench-apartment"
CONFIG="$RUN_DIR/terminator.config"
PID_FILE="$RUN_DIR/terminator.pid"
USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/terminator/config"

DOCKER_CMD='docker run --rm -it --network host -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}" -e FASTDDS_BUILTIN_TRANSPORTS=UDPv4 -v "$PWD:/workspace" vla-bench-ros bash'

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Command each pane runs; the docker pane only gets it typed in.
pane_command() {
  case "$1" in
    sim) echo "./scripts/ros.sh sim --robot turtlebot3 --world apartment_layout --x 4.3 --y 7.0" ;;
    teleop) echo "export TURTLEBOT3_MODEL=waffle_pi && ros2 run turtlebot3_teleop teleop_keyboard" ;;
    rviz) echo "ros2 run rviz2 rviz2 -d sim/rviz/sensors.rviz --ros-args -p use_sim_time:=true" ;;
    docker) echo "$DOCKER_CMD" ;;
  esac
}

# Runs inside each Terminator pane: source ROS, run (or type) the pane's
# command, then leave an interactive shell that keeps the ROS environment.
pane() {
  local name="$1" cmd
  cmd="$(pane_command "$name")"

  set +u
  # shellcheck disable=SC1090
  source "/opt/ros/$ROS_DISTRO_EXPECTED/setup.bash"
  # shellcheck disable=SC1091
  [[ -f "$ROOT/ros_ws/install/setup.bash" ]] && source "$ROOT/ros_ws/install/setup.bash"
  set -u
  cd "$ROOT"

  if [[ -n "$cmd" && "$name" != docker ]]; then
    echo "\$ $cmd"
    # Ctrl-C stops the command but not this pane.
    trap : INT
    eval "$cmd" || true
    trap - INT
    exec "$SHELL" -i
  fi

  if [[ -n "$cmd" ]]; then
    export APT_TYPED="$cmd"
    case "${SHELL##*/}" in
      zsh) export ZDOTDIR="$RUN_DIR/zsh"; exec "$SHELL" -i ;;
      bash) exec "$SHELL" --rcfile "$RUN_DIR/bashrc" -i ;;
      *) echo "Run: $cmd" ;;
    esac
  fi
  exec "$SHELL" -i
}

# Anchored so shells that merely mention these commands do not match.
GZ_PATTERN='^(gz|ruby \S+/gz) sim '
LAUNCH_PATTERN='^\S*python3 \S+/ros2 launch \S*sim/launch/sim\.launch\.py'

gz_running() {
  pgrep -f "$GZ_PATTERN" >/dev/null
}

window_pid() {
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null)" || return 1
  [[ -n "$pid" ]] && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q terminator || return 1
  echo "$pid"
}

stop() {
  # Same as Ctrl-C in the sim pane: ros2 launch shuts Gazebo down cleanly.
  if pkill -INT -f "$LAUNCH_PATTERN"; then
    echo "Stopping the sim..."
    for _ in $(seq 1 20); do
      gz_running || break
      sleep 1
    done
  fi

  local pid
  if pid="$(window_pid)"; then
    kill "$pid"
  fi
  rm -f "$PID_FILE"

  if gz_running; then
    echo "Killing leftover Gazebo processes."
    pkill -f "$GZ_PATTERN" || true
  fi
}

# Shell startup files that type APT_TYPED at the first prompt.
write_rc_files() {
  mkdir -p "$RUN_DIR/zsh"

  cat >"$RUN_DIR/zsh/.zshenv" <<'EOF'
[[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
EOF

  cat >"$RUN_DIR/zsh/.zshrc" <<'EOF'
ZDOTDIR="$HOME"
[[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"
print -z -- "$APT_TYPED"
unset APT_TYPED
EOF

  cat >"$RUN_DIR/bashrc" <<'EOF'
[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"
history -s "$APT_TYPED"
echo "Press Up, then Enter, to run: $APT_TYPED"
unset APT_TYPED
EOF
}

# The user's Terminator config (profiles, keybindings) plus an "apartment"
# layout: two columns of three panes.
write_config() {
  python3 - "$USER_CONFIG" "$CONFIG" "$ROOT" <<'EOF'
import os
import shlex
import sys

from configobj import ConfigObj

user_config, out, root = sys.argv[1:]
config = ConfigObj(user_config if os.path.isfile(user_config) else None)
config.filename = out
config.setdefault('layouts', {})

TELEOP_UUID = 'a7c1e3d0-5b2f-4c1e-9a6d-7f0b8e2c4d11'
script = shlex.quote(os.path.join(root, 'scripts', 'apartment.sh'))

layout = {
    'window0': {
        'type': 'Window', 'parent': '', 'title': 'vla-bench apartment',
        'size': ['1600', '1000'], 'last_active_term': TELEOP_UUID,
    },
    'columns': {'type': 'HPaned', 'parent': 'window0', 'order': '0', 'ratio': '0.5'},
}
for side, (top, middle, bottom) in enumerate((('sim', 'rviz', 'shell1'),
                                              ('teleop', 'docker', 'shell2'))):
    upper, lower = f'col{side}', f'col{side}_lower'
    layout[upper] = {'type': 'VPaned', 'parent': 'columns', 'order': str(side), 'ratio': '0.333'}
    layout[lower] = {'type': 'VPaned', 'parent': upper, 'order': '1', 'ratio': '0.5'}
    for name, parent, order in ((top, upper, 0), (middle, lower, 0), (bottom, lower, 1)):
        layout[name] = {
            'type': 'Terminal', 'parent': parent, 'order': str(order), 'profile': 'default',
            'title': name, 'directory': root, 'command': f'{script} --pane {name}',
        }
layout['teleop']['uuid'] = TELEOP_UUID

config['layouts']['apartment'] = layout
config.write()
EOF
}

case "${1:-}" in
  --pane) pane "${2:?--pane needs a name}" ;;
  stop) stop ;;
  "")
    command -v terminator >/dev/null || die "terminator is not installed: sudo apt install terminator"
    [[ -f "/opt/ros/$ROS_DISTRO_EXPECTED/setup.bash" ]] || die "ROS $ROS_DISTRO_EXPECTED not found. Run: scripts/ros.sh setup"
    window_pid >/dev/null && die "The apartment window is already open (scripts/apartment.sh stop to close it)."
    gz_running && die "Gazebo is already running; stop it with: scripts/apartment.sh stop"

    write_rc_files
    write_config
    # -u: own process, so this config is used and stop can close the window.
    setsid terminator -u -g "$CONFIG" -l apartment </dev/null >/dev/null 2>&1 &
    echo $! >"$PID_FILE"
    ;;
  *) die "Usage: scripts/apartment.sh [stop]" ;;
esac
