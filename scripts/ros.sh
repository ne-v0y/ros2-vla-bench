#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_WS="$ROOT/ros_ws"

ROS_DISTRO_EXPECTED="${ROS_DISTRO_EXPECTED:-jazzy}"

log() {
  printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARN:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage:
  scripts/ros.sh setup
  scripts/ros.sh build
  scripts/ros.sh doctor
  scripts/ros.sh smoke
  scripts/ros.sh shell
  scripts/ros.sh run <package> <executable> [args...]
  scripts/ros.sh launch <package> <launch_file> [args...]

Commands:
  setup
      Install missing ROS 2 Jazzy + Gazebo dependencies on Ubuntu 24.04,
      initialize rosdep, install workspace deps, and build the workspace.

  build
      Resolve dependencies and run colcon build.

  doctor
      Print ROS / Gazebo diagnostics.

  smoke
      Launch an empty Gazebo world through ros_gz_sim.

  shell
      Open an interactive shell with ROS + this workspace sourced.

  run
      Run:
        ros2 run <package> <executable>

  launch
      Run:
        ros2 launch <package> <launch_file>

Environment:
  ROS_DISTRO_EXPECTED
      Defaults to jazzy.
USAGE
}

load_os() {
  [[ -f /etc/os-release ]] || die "Cannot detect Linux distribution."
  # shellcheck disable=SC1091
  source /etc/os-release
}

ensure_supported_os() {
  load_os

  if [[ "${ID:-}" != "ubuntu" || "${VERSION_CODENAME:-}" != "noble" ]]; then
    die "Automatic install currently supports Ubuntu 24.04 Noble only. Detected: ${PRETTY_NAME:-unknown}"
  fi
}

ros_installed() {
  [[ -f "/opt/ros/$ROS_DISTRO_EXPECTED/setup.bash" ]]
}

ensure_ros_apt_source() {
  if apt-cache policy 2>/dev/null | grep -q "packages.ros.org"; then
    return
  fi

  ensure_supported_os

  log "Installing ROS apt source"

  sudo apt update
  sudo apt install -y \
    curl \
    software-properties-common

  sudo add-apt-repository -y universe

  local version

  version="$(
    curl -fsSL \
      https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
      | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'
  )"

  [[ -n "$version" ]] || die "Could not determine ros-apt-source release."

  curl -fsSL \
    -o /tmp/ros2-apt-source.deb \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${version}/ros2-apt-source_${version}.noble_all.deb"

  sudo dpkg -i /tmp/ros2-apt-source.deb
  sudo apt update
}

install_ros() {
  ensure_supported_os
  ensure_ros_apt_source

  log "Installing ROS 2 $ROS_DISTRO_EXPECTED + Gazebo integration"

  sudo apt update

  sudo apt install -y \
    "ros-${ROS_DISTRO_EXPECTED}-desktop" \
    "ros-${ROS_DISTRO_EXPECTED}-ros-gz" \
    "ros-${ROS_DISTRO_EXPECTED}-gz-tools-vendor" \
    "ros-${ROS_DISTRO_EXPECTED}-gz-sim-vendor" \
    "ros-${ROS_DISTRO_EXPECTED}-xacro" \
    "ros-${ROS_DISTRO_EXPECTED}-robot-state-publisher" \
    "ros-${ROS_DISTRO_EXPECTED}-cv-bridge" \
    "ros-${ROS_DISTRO_EXPECTED}-image-transport" \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool \
    build-essential \
    cmake \
    git
}

source_ros() {
  [[ -f "/opt/ros/$ROS_DISTRO_EXPECTED/setup.bash" ]] \
    || die "ROS $ROS_DISTRO_EXPECTED not found. Run: scripts/ros.sh setup"

  set +u

  # shellcheck disable=SC1091
  source "/opt/ros/$ROS_DISTRO_EXPECTED/setup.bash"

  if [[ -f "$ROS_WS/install/setup.bash" ]]; then
    # shellcheck disable=SC1091
    source "$ROS_WS/install/setup.bash"
  fi

  set -u
}

init_rosdep() {
  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    log "Initializing rosdep"
    sudo rosdep init
  fi

  log "Updating rosdep"
  rosdep update
}

install_workspace_dependencies() {
  source_ros

  if find "$ROS_WS/src" -mindepth 1 -maxdepth 1 | read -r; then
    log "Installing workspace dependencies"

    rosdep install \
      --from-paths "$ROS_WS/src" \
      --ignore-src \
      -r \
      -y \
      --rosdistro "$ROS_DISTRO_EXPECTED"
  else
    warn "ros_ws/src is empty; skipping rosdep install."
  fi
}

build_workspace() {
  source_ros

  mkdir -p "$ROS_WS/src"

  install_workspace_dependencies

  log "Building ROS workspace"

  cd "$ROS_WS"

  colcon build \
    --symlink-install \
    --event-handlers console_direct+
}

doctor() {
  load_os

  echo "OS:              ${PRETTY_NAME:-unknown}"
  echo "Expected ROS:    $ROS_DISTRO_EXPECTED"
  echo "Workspace:       $ROS_WS"
  echo "ROS installed:   $(ros_installed && echo yes || echo no)"

  if ros_installed; then
    source_ros

    echo "ROS_DISTRO:      ${ROS_DISTRO:-unset}"
    echo "ros2:            $(command -v ros2 || echo missing)"
    echo "gz:              $(command -v gz || echo missing)"
    echo "ros_gz_sim:      $(ros2 pkg prefix ros_gz_sim 2>/dev/null || echo missing)"
    echo "ros_gz_bridge:   $(ros2 pkg prefix ros_gz_bridge 2>/dev/null || echo missing)"
    echo

    gz sim --version 2>/dev/null || true
  fi
}

setup() {
  if ! ros_installed; then
    install_ros
  else
    log "ROS $ROS_DISTRO_EXPECTED already installed"
  fi

  source_ros

  if ! ros2 pkg prefix ros_gz_sim >/dev/null 2>&1; then
    ensure_supported_os
    ensure_ros_apt_source

    log "ros_gz not found; installing Gazebo integration"

    sudo apt update

    sudo apt install -y \
      "ros-${ROS_DISTRO_EXPECTED}-ros-gz" \
      "ros-${ROS_DISTRO_EXPECTED}-gz-tools-vendor" \
      "ros-${ROS_DISTRO_EXPECTED}-gz-sim-vendor"
  fi

  init_rosdep
  build_workspace

  log "ROS / Gazebo setup complete"
  doctor

  echo
  echo "Run smoke test with:"
  echo "  $ROOT/scripts/ros.sh smoke"
}

smoke() {
  source_ros

  ros2 pkg prefix ros_gz_sim >/dev/null 2>&1 \
    || die "ros_gz_sim is unavailable. Run: scripts/ros.sh setup"

  log "Launching Gazebo empty world"

  echo "Close Gazebo or press Ctrl-C when finished."

  ros2 launch \
    ros_gz_sim \
    gz_sim.launch.py \
    gz_args:="-r empty.sdf"
}

command="${1:-}"

case "$command" in
  setup)
    setup
    ;;

  build)
    build_workspace
    ;;

  doctor)
    doctor
    ;;

  smoke)
    smoke
    ;;

  shell)
    source_ros
    exec "${SHELL:-/bin/bash}"
    ;;

  run)
    shift

    [[ $# -ge 2 ]] \
      || die "Usage: scripts/ros.sh run <package> <executable> [args...]"

    source_ros
    exec ros2 run "$@"
    ;;

  launch)
    shift

    [[ $# -ge 2 ]] \
      || die "Usage: scripts/ros.sh launch <package> <launch_file> [args...]"

    source_ros
    exec ros2 launch "$@"
    ;;

  ""|-h|--help|help)
    usage
    ;;

  *)
    die "Unknown command: $command"
    ;;
esac
