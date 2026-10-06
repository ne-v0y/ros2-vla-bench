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

Run a Gazebo smoke test:

```bash
./scripts/ros.sh smoke
```

Build ROS packages:

```bash
./scripts/ros.sh build
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
