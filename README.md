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

### Robot control

The workspace includes a small `vla_bench_control` ROS 2 package that publishes
`geometry_msgs/Twist` commands. Build it once:

```bash
./scripts/ros.sh build --packages-select vla_bench_control
```

With a simulated robot running, send discrete motion commands:

```bash
./scripts/ros.sh control forward
./scripts/ros.sh control backward --duration 0.5
./scripts/ros.sh control left --duration 0.5
./scripts/ros.sh control right --duration 0.5
./scripts/ros.sh control stop
```

Defaults are 0.20 m/s linear speed, 0.60 rad/s angular speed, a 1 second duration,
and the `/cmd_vel` topic. Override them with `--linear`, `--angular`,
`--duration`, `--rate`, and `--topic`.

This intentionally exposes a tiny action vocabulary that can later sit behind a
VLM/VLA policy:

```text
model output -> forward | backward | left | right | stop
                         |
                         v
                    geometry_msgs/Twist
                         |
                         v
                      /cmd_vel
```

The control utility always publishes a zero-velocity command at the end of each
motion command so the robot does not keep moving after the command finishes.

### Sensor fusion

The human-view robot exposes wheel joint states and an IMU. Run the fusion stack
in a second shell:

```bash
./scripts/ros.sh build --packages-select vla_bench_perception
./scripts/ros.sh fusion
```

`wheel_odometry_node` is parameterized for wheel radius/separation and publishes
`/vla_bench/wheel/odom_estimated`. A `robot_localization` EKF combines wheel
velocity with IMU yaw/yaw-rate and publishes `/vla_bench/fused/odom`. This keeps
the benchmark interface independent from Gazebo's ground-truth `/odom`.

### VLA integration

The `vla_bench_vla` package defines a small ROS contract between the simulator
and any model adapter. Start it after simulation and fusion:

```bash
./scripts/ros.sh build --packages-select vla_bench_vla
./scripts/ros.sh vla
```

The bridge publishes `/vla_bench/vla/observation` as compact JSON containing
the current instruction, fused pose/twist, lidar sector minima, and metadata for
the latest RGB frame. The RGB pixels stay on `/camera/image_raw`, so a model
runner can consume the native image without base64 duplication.

The model publishes exactly one of `FORWARD`, `BACKWARD`, `LEFT`, `RIGHT`,
or `STOP` to `/vla_bench/vla/action`. For example:

```bash
ros2 topic pub --once /vla_bench/vla/instruction std_msgs/msg/String "{data: 'Walk toward the sofa'}"
ros2 topic echo /vla_bench/vla/observation
ros2 topic pub --once /vla_bench/vla/action std_msgs/msg/String "{data: 'FORWARD'}"
```

Actions automatically time out to STOP. The bridge also rejects FORWARD when
the front lidar sector is closer than 0.45 m (or scan data is missing), providing
a minimal safety layer around model output.

```text
RGB image ---------------------------> model adapter
                                         |
fused odom + lidar + instruction --------+--> VLA/VLM
                                         |
                                         v
                               FORWARD|BACKWARD|LEFT|RIGHT|STOP
                                         |
                                         v
                                  VLA ROS bridge
                                   /cmd_vel
```

### Simulation: robots and worlds

Launch a Gazebo world with a robot. The default is the benchmark-owned
`human_view` mobile base: its camera is mounted at 1.62 m so recorded video
has an adult eye-level viewpoint rather than a tabletop robot viewpoint.

```bash
./scripts/ros.sh sim --world apartment_layout
./scripts/ros.sh sim --robot turtlebot3 --world house
./scripts/ros.sh sim --robot turtlebot4 --world warehouse --model lite --headless
./scripts/ros.sh sim --robot none --world ./my_world.sdf
./scripts/ros.sh sim --list
```

| Robot (`--robot`) | Models (`--model`) | Native worlds (`--world`) |
| --- | --- | --- |
| `human_view` (default) | `standard` | any Gazebo world; camera 1.62 m, lidar 0.95 m, IMU + wheel odom |
| `turtlebot3` | `waffle` (default), `waffle_pi`, `burger` (no camera) | `house`, `turtlebot3_world`, `tb3_empty`, `dqn_stage1`..`dqn_stage4` |
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

### Apartment demo

[`sim/worlds/apartment_layout.world`](sim/worlds/apartment_layout.world) is a furnished apartment
(living room, bedrooms, bathroom, entry, storage and balcony). Open the whole scenario in one
Terminator window with six titled panes:

```bash
./scripts/apartment.sh        # open the window
./scripts/apartment.sh stop   # stop the sim, close the window, kill leftover Gazebo
```

| Pane | Runs |
| --- | --- |
| `sim` | `./scripts/ros.sh sim --robot human_view --world apartment_layout --x 4.3 --y 7.0` |
| `teleop` | `ros2 run teleop_twist_keyboard teleop_twist_keyboard` (focused on start) |
| `rviz` | `ros2 run rviz2 rviz2` with [`sim/rviz/sensors.rviz`](sim/rviz/sensors.rviz): camera image, laser scan, robot model, TF |
| `docker` | the `vla-bench-ros` container command, typed but not run; press Enter to start it |
| `shell1`, `shell2` | spare shells |

ROS and the workspace are sourced in every pane. Ctrl-C stops a pane's command and leaves a shell
in that pane. The window uses your `~/.config/terminator/config` profiles and keybindings plus a
generated `apartment` layout; your config file is not modified. Use `stop` rather than closing the
window: closing it can leave Gazebo running, and the script refuses to start while Gazebo is
already running.

The container command (needs the `vla-bench-ros` image built from `Dockerfile.ros`):

```bash
docker run --rm -it \
  --network host \
  -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}" \
  -e FASTDDS_BUILTIN_TRANSPORTS=UDPv4 \
  -v "$PWD:/workspace" \
  vla-bench-ros \
  bash
```

Without the script, `./scripts/ros.sh sim --world apartment_layout` spawns the human-view robot at the same spot.

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
