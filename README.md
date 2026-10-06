# VLA Bench

A lightweight, pluggable benchmark platform for VLA / VLM robotics evaluation.

The core project intentionally does not download:

- model weights
- benchmark datasets
- benchmark-specific simulators
- third-party benchmark repositories

Those belong in plugins or user-managed environments.

## Create the Python environment

```bash
./scripts/bootstrap.sh
source .venv/bin/activate
```

## ROS 2 + Gazebo

Automatic installation currently targets:

- Ubuntu 24.04 Noble
- ROS 2 Jazzy
- Gazebo Harmonic through `ros_gz`

Install missing ROS / Gazebo dependencies:

```bash
./scripts/ros.sh setup
```

Check installation:

```bash
./scripts/ros.sh doctor
```

Run a Gazebo smoke test (add `--headless` over SSH / CI):

```bash
./scripts/ros.sh smoke
```

Build ROS packages (`--skip-deps` skips rosdep; extra args go to colcon):

```bash
./scripts/ros.sh build
./scripts/ros.sh build --skip-deps --packages-select <package>
```

Remove `ros_ws/build`, `ros_ws/install` and `ros_ws/log`:

```bash
./scripts/ros.sh clean
```

Run a ROS node:

```bash
./scripts/ros.sh run <package> <executable>
```

Launch a ROS package:

```bash
./scripts/ros.sh launch <package> <launch_file>
```

Open a sourced ROS shell:

```bash
./scripts/ros.sh shell
```

### Simulation: robots and worlds

Launch a Gazebo world with a robot:

```bash
./scripts/ros.sh sim --robot turtlebot3 --world house
./scripts/ros.sh sim --robot turtlebot4 --world warehouse --model lite --headless
./scripts/ros.sh sim --robot none --world ./my_world.sdf
./scripts/ros.sh sim --list
```

| Robot (`--robot`) | Models (`--model`) | Native worlds (`--world`) |
| --- | --- | --- |
| `turtlebot3` (default) | `waffle` (default), `waffle_pi`, `burger` (no camera) | `house`, `turtlebot3_world`, `tb3_empty`, `dqn_stage1`..`dqn_stage4` |
| `turtlebot4` | `standard` (default), `lite` | `warehouse`, `depot`, `maze` |
| `none` | | any |

- `--world` defaults to `empty`, Gazebo's built-in empty world.
- Custom worlds: put `<name>.sdf` in `sim/worlds/` and use `--world <name>`, or pass a path to any
  `.sdf` / `.world` file.
- The first time you choose a robot or world whose package is missing, it is installed with apt
  (`ros-jazzy-turtlebot3-gazebo` or `ros-jazzy-turtlebot4-simulator`), which needs sudo.
- `--x` / `--y` set the spawn position (each world has a sensible default); `--yaw` works for
  TurtleBot4 only.
- Extra `key:=value` arguments are passed to the launch, e.g. `nav2:=true rviz:=true` for TurtleBot4.
- `SIM_ROBOT` and `SIM_WORLD` change the defaults.
- You can mix robots and worlds from different sets, but the native pairings in the table are the
  most reliable.

The launch file is [`sim/launch/sim.launch.py`](sim/launch/sim.launch.py); it can also be run directly
with `ros2 launch sim/launch/sim.launch.py robot:=turtlebot3 world:=house`.

## Architecture

```text
                 CLI / API
                    |
             Evaluation Core
              /           \
     ModelAdapter       BenchmarkAdapter
                              |
                    native simulator / ROS
```

A published benchmark plugin should keep the benchmark's native simulator and evaluation
protocol when producing results intended to compare with published numbers.

Gazebo support is intended for:

- ROS integration
- custom benchmark tasks
- embodied VLM experiments
- VLA policy testing
- custom simulation environments
