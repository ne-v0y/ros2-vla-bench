#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROS_WS="$ROOT/ros_ws"

ROS_DISTRO_EXPECTED="${ROS_DISTRO_EXPECTED:-jazzy}"
ROS_SETUP="/opt/ros/$ROS_DISTRO_EXPECTED/setup.bash"

# Gazebo integration packages; also used to repair a partial install.
GZ_PACKAGES=(
  "ros-${ROS_DISTRO_EXPECTED}-ros-gz"
  "ros-${ROS_DISTRO_EXPECTED}-gz-tools-vendor"
  "ros-${ROS_DISTRO_EXPECTED}-gz-sim-vendor"
)

ROS_PACKAGES=(
  "ros-${ROS_DISTRO_EXPECTED}-desktop"
  "${GZ_PACKAGES[@]}"
  "ros-${ROS_DISTRO_EXPECTED}-xacro"
  "ros-${ROS_DISTRO_EXPECTED}-robot-state-publisher"
  "ros-${ROS_DISTRO_EXPECTED}-cv-bridge"
  "ros-${ROS_DISTRO_EXPECTED}-image-transport"
  python3-colcon-common-extensions
  python3-rosdep
  python3-vcstool
  build-essential
  cmake
  git
)

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_BLUE=$'\033[1;34m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_RESET=$'\033[0m'
else
  C_BLUE='' C_YELLOW='' C_RED='' C_RESET=''
fi

log() {
  printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"
}

warn() {
  printf '\n%sWARN:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
}

die() {
  printf '\n%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage:
  scripts/ros.sh setup
  scripts/ros.sh build [--skip-deps] [colcon args...]
  scripts/ros.sh clean
  scripts/ros.sh doctor
  scripts/ros.sh smoke [--headless]
  scripts/ros.sh sim [--robot R] [--world W] [--model M] [--headless]
                     [--x X] [--y Y] [--yaw YAW] [key:=value...]
  scripts/ros.sh sim --list
  scripts/ros.sh shell
  scripts/ros.sh run <package> <executable> [args...]
  scripts/ros.sh launch <package> <launch_file> [args...]

Commands:
  setup
      Install missing ROS 2 + Gazebo dependencies on Ubuntu,
      initialize rosdep, install workspace deps, and build the workspace.

  build
      Resolve dependencies (unless --skip-deps) and run colcon build.
      Extra arguments are passed to colcon, e.g.:
        scripts/ros.sh build --packages-select my_pkg

  clean
      Remove ros_ws/build, ros_ws/install and ros_ws/log.

  doctor
      Print ROS / Gazebo diagnostics.

  smoke
      Launch an empty Gazebo world through ros_gz_sim.
      --headless runs the server only (no GUI), for SSH / CI.

  sim
      Launch a Gazebo world with a robot (sim/launch/sim.launch.py).
      Missing robot / world packages are installed via apt on first use.
        scripts/ros.sh sim --robot turtlebot3 --world house
        scripts/ros.sh sim --robot turtlebot4 --world warehouse --headless
        scripts/ros.sh sim --robot none --world ./my_world.sdf
      --robot     turtlebot3 (default) | turtlebot4 | none
      --world     empty (default) | house | warehouse | ... | <path.sdf>
      --model     turtlebot3: waffle | waffle_pi | burger
                  turtlebot4: standard | lite
      --x/--y     spawn position (defaults depend on the world)
      --yaw       spawn heading (turtlebot4 only)
      --list      show all robots and worlds
      key:=value  extra launch arguments, e.g. nav2:=true for turtlebot4

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
  SIM_ROBOT, SIM_WORLD
      Default robot / world for the sim command.
  NO_COLOR
      Disable colored output.
USAGE
}

# Run as root directly, otherwise through sudo.
as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

load_os() {
  [[ -f /etc/os-release ]] || die "Cannot detect Linux distribution."
  # shellcheck disable=SC1091
  source /etc/os-release
}

# Ubuntu codename that the expected ROS distro ships binaries for.
expected_codename() {
  case "$ROS_DISTRO_EXPECTED" in
    humble) echo jammy ;;
    jazzy | kilted | rolling) echo noble ;;
    *) die "Unsupported ROS distro: $ROS_DISTRO_EXPECTED" ;;
  esac
}

ensure_supported_os() {
  load_os

  local codename
  codename="$(expected_codename)"

  if [[ "${ID:-}" != "ubuntu" || "${VERSION_CODENAME:-}" != "$codename" ]]; then
    die "Automatic install of ROS $ROS_DISTRO_EXPECTED requires Ubuntu $codename. Detected: ${PRETTY_NAME:-unknown}"
  fi
}

ros_installed() {
  [[ -f "$ROS_SETUP" ]]
}

ros_apt_source_installed() {
  dpkg-query -W -f='${Status}' ros2-apt-source 2>/dev/null | grep -q "install ok installed" \
    || apt-cache policy 2>/dev/null | grep -q "packages.ros.org"
}

ensure_ros_apt_source() {
  ros_apt_source_installed && return

  ensure_supported_os

  log "Installing ROS apt source"

  as_root apt-get update
  as_root apt-get install -y curl software-properties-common
  as_root add-apt-repository -y universe

  local version tmp_dir

  version="$(
    curl -fsSL \
      https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
      | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p'
  )"

  [[ -n "$version" ]] || die "Could not determine ros-apt-source release (GitHub API rate limit?)."

  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" RETURN

  curl -fsSL \
    -o "$tmp_dir/ros2-apt-source.deb" \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${version}/ros2-apt-source_${version}.${VERSION_CODENAME}_all.deb"

  as_root dpkg -i "$tmp_dir/ros2-apt-source.deb"
}

apt_install() {
  ensure_supported_os
  ensure_ros_apt_source

  as_root apt-get update
  as_root apt-get install -y "$@"
}

install_ros() {
  log "Installing ROS 2 $ROS_DISTRO_EXPECTED + Gazebo integration"
  apt_install "${ROS_PACKAGES[@]}"
}

source_ros() {
  ros_installed || die "ROS $ROS_DISTRO_EXPECTED not found. Run: scripts/ros.sh setup"

  if [[ -n "${ROS_DISTRO:-}" && "$ROS_DISTRO" != "$ROS_DISTRO_EXPECTED" ]]; then
    warn "Environment already has ROS_DISTRO=$ROS_DISTRO sourced; expected $ROS_DISTRO_EXPECTED. Use a fresh shell to avoid mixing distros."
  fi

  set +u

  # shellcheck disable=SC1090
  source "$ROS_SETUP"

  if [[ -f "$ROS_WS/install/setup.bash" ]]; then
    # shellcheck disable=SC1091
    source "$ROS_WS/install/setup.bash"
  fi

  set -u
}

has_pkg() {
  ros2 pkg prefix "$1" >/dev/null 2>&1
}

init_rosdep() {
  if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
    log "Initializing rosdep"
    as_root rosdep init
  fi

  log "Updating rosdep"
  rosdep update --rosdistro "$ROS_DISTRO_EXPECTED"
}

install_workspace_dependencies() {
  source_ros

  if [[ -z "$(find "$ROS_WS/src" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    warn "ros_ws/src is empty; skipping rosdep install."
    return
  fi

  log "Installing workspace dependencies"

  rosdep install \
    --from-paths "$ROS_WS/src" \
    --ignore-src \
    -r \
    -y \
    --rosdistro "$ROS_DISTRO_EXPECTED"
}

build_workspace() {
  local skip_deps=0

  if [[ "${1:-}" == "--skip-deps" ]]; then
    skip_deps=1
    shift
  fi

  mkdir -p "$ROS_WS/src"

  source_ros

  if [[ $skip_deps -eq 0 ]]; then
    install_workspace_dependencies
  fi

  log "Building ROS workspace"

  cd "$ROS_WS"

  colcon build \
    --symlink-install \
    --event-handlers console_direct+ \
    "$@"
}

clean_workspace() {
  log "Removing build artifacts in $ROS_WS"
  rm -rf "$ROS_WS/build" "$ROS_WS/install" "$ROS_WS/log"
}

doctor() {
  load_os

  echo "OS:              ${PRETTY_NAME:-unknown}"
  echo "Expected ROS:    $ROS_DISTRO_EXPECTED"
  echo "Workspace:       $ROS_WS"
  echo "Workspace built: $([[ -f "$ROS_WS/install/setup.bash" ]] && echo yes || echo no)"
  echo "ROS installed:   $(ros_installed && echo yes || echo no)"

  if ros_installed; then
    source_ros

    echo "ROS_DISTRO:      ${ROS_DISTRO:-unset}"
    echo "RMW:             ${RMW_IMPLEMENTATION:-default}"
    echo "ROS_DOMAIN_ID:   ${ROS_DOMAIN_ID:-0}"
    echo "ros2:            $(command -v ros2 || echo missing)"
    echo "colcon:          $(command -v colcon || echo missing)"
    echo "rosdep:          $(command -v rosdep || echo missing)"
    echo "gz:              $(command -v gz || echo missing)"
    echo "ros_gz_sim:      $(ros2 pkg prefix ros_gz_sim 2>/dev/null || echo missing)"
    echo "ros_gz_bridge:   $(ros2 pkg prefix ros_gz_bridge 2>/dev/null || echo missing)"
    echo "Display:         ${DISPLAY:-${WAYLAND_DISPLAY:-none (use: smoke --headless)}}"
    echo

    gz sim --version 2>/dev/null || true
  fi
}

setup() {
  if ros_installed; then
    log "ROS $ROS_DISTRO_EXPECTED already installed"
  else
    install_ros
  fi

  source_ros

  if ! has_pkg ros_gz_sim; then
    log "ros_gz not found; installing Gazebo integration"
    apt_install "${GZ_PACKAGES[@]}"
    source_ros
  fi

  init_rosdep
  build_workspace

  log "ROS / Gazebo setup complete"
  doctor

  echo
  echo "Run smoke test with:"
  echo "  $ROOT/scripts/ros.sh smoke"
}

# ROS package that provides each robot, and the apt package that installs it.
robot_ros_pkg() {
  case "$1" in
    turtlebot3) echo turtlebot3_gazebo ;;
    turtlebot4) echo turtlebot4_gz_bringup ;;
    none) echo "" ;;
    *) ;;
  esac
}

robot_apt_pkg() {
  case "$1" in
    turtlebot3) echo "ros-${ROS_DISTRO_EXPECTED}-turtlebot3-gazebo" ;;
    turtlebot4) echo "ros-${ROS_DISTRO_EXPECTED}-turtlebot4-simulator" ;;
  esac
}

# ROS package that provides each built-in world, if any.
world_ros_pkg() {
  case "$1" in
    house | turtlebot3_world | tb3_empty | dqn_stage[1-4]) echo turtlebot3_gazebo ;;
    warehouse | depot | maze) echo turtlebot4_gz_bringup ;;
  esac
}

world_apt_pkg() {
  case "$(world_ros_pkg "$1")" in
    turtlebot3_gazebo) robot_apt_pkg turtlebot3 ;;
    turtlebot4_gz_bringup) robot_apt_pkg turtlebot4 ;;
  esac
}

ensure_ros_pkg() {
  local ros_pkg="$1" apt_pkg="$2"

  [[ -z "$ros_pkg" ]] && return
  has_pkg "$ros_pkg" && return

  log "$ros_pkg not found; installing $apt_pkg"
  apt_install "$apt_pkg"
  source_ros
  has_pkg "$ros_pkg" || die "$ros_pkg still unavailable after installing $apt_pkg"
}

sim_list() {
  cat <<LIST
Robots (--robot):
  turtlebot3   models: waffle (default, camera), waffle_pi, burger (no camera)
  turtlebot4   models: standard (default), lite
  none         world only

Worlds (--world):
  empty              Gazebo built-in empty world
  tb3_empty          TurtleBot3 empty world
  house              TurtleBot3 house
  turtlebot3_world   TurtleBot3 hexagon arena
  dqn_stage1..4      TurtleBot3 DQN stages
  warehouse          TurtleBot4 warehouse
  depot              TurtleBot4 depot
  maze               TurtleBot4 maze
  <name>             $ROOT/sim/worlds/<name>.sdf or .world
  <path>             any .sdf / .world file

Robots and worlds can be mixed freely; native pairings are the most reliable.
LIST

  if compgen -G "$ROOT/sim/worlds/*.sdf" >/dev/null || compgen -G "$ROOT/sim/worlds/*.world" >/dev/null; then
    echo
    echo "Custom worlds in sim/worlds:"
    for f in "$ROOT"/sim/worlds/*.sdf "$ROOT"/sim/worlds/*.world; do
      [[ -f "$f" ]] && echo "  $(basename "${f%.*}")"
    done
  fi
}

sim() {
  local robot="${SIM_ROBOT:-turtlebot3}"
  local world="${SIM_WORLD:-empty}"
  local model="" headless=false x="" y="" yaw=""
  local extra=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r | --robot) robot="${2:?--robot needs a value}"; shift 2 ;;
      -w | --world) world="${2:?--world needs a value}"; shift 2 ;;
      -m | --model) model="${2:?--model needs a value}"; shift 2 ;;
      --x) x="${2:?--x needs a value}"; shift 2 ;;
      --y) y="${2:?--y needs a value}"; shift 2 ;;
      --yaw) yaw="${2:?--yaw needs a value}"; shift 2 ;;
      --headless) headless=true; shift ;;
      --list) sim_list; return ;;
      -h | --help) usage; return ;;
      *:=*) extra+=("$1"); shift ;;
      *) die "Unknown sim option: $1 (launch arguments use key:=value)" ;;
    esac
  done

  case "$robot" in
    turtlebot3 | turtlebot4 | none) ;;
    *) die "Unknown robot: $robot (see: scripts/ros.sh sim --list)" ;;
  esac

  source_ros

  has_pkg ros_gz_sim || die "ros_gz_sim is unavailable. Run: scripts/ros.sh setup"

  ensure_ros_pkg "$(robot_ros_pkg "$robot")" "$(robot_apt_pkg "$robot")"
  ensure_ros_pkg "$(world_ros_pkg "$world")" "$(world_apt_pkg "$world")"

  if [[ "$headless" == false && -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    warn "No display detected; the Gazebo GUI may fail. Add --headless to run server only."
  fi

  local args=(robot:="$robot" world:="$world" headless:="$headless")
  [[ -n "$model" ]] && args+=(model:="$model")
  [[ -n "$x" ]] && args+=(x:="$x")
  [[ -n "$y" ]] && args+=(y:="$y")
  [[ -n "$yaw" ]] && args+=(yaw:="$yaw")

  log "Launching $robot in world '$world'"
  echo "Close Gazebo or press Ctrl-C when finished."

  exec ros2 launch "$ROOT/sim/launch/sim.launch.py" "${args[@]}" "${extra[@]}"
}

smoke() {
  case "${1:-}" in
    --headless | "") ;;
    *) die "Unknown smoke option: $1" ;;
  esac

  sim --robot none --world empty "$@"
}

command="${1:-}"
[[ $# -gt 0 ]] && shift

case "$command" in
  setup)
    setup
    ;;

  build)
    build_workspace "$@"
    ;;

  clean)
    clean_workspace
    ;;

  doctor)
    doctor
    ;;

  smoke)
    smoke "$@"
    ;;

  sim)
    sim "$@"
    ;;

  shell)
    source_ros
    log "ROS $ROS_DISTRO_EXPECTED environment loaded (exit to leave)"
    exec "${SHELL:-/bin/bash}"
    ;;

  run)
    [[ $# -ge 2 ]] \
      || die "Usage: scripts/ros.sh run <package> <executable> [args...]"

    source_ros
    exec ros2 run "$@"
    ;;

  launch)
    [[ $# -ge 2 ]] \
      || die "Usage: scripts/ros.sh launch <package> <launch_file> [args...]"

    source_ros
    exec ros2 launch "$@"
    ;;

  "" | -h | --help | help)
    usage
    ;;

  *)
    usage >&2
    die "Unknown command: $command"
    ;;
esac
