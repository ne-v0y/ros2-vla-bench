"""Compose a Gazebo world with an optional robot.

Usage (normally via scripts/ros.sh sim):
  ros2 launch sim/launch/sim.launch.py robot:=turtlebot3 world:=house
  ros2 launch sim/launch/sim.launch.py robot:=turtlebot4 world:=warehouse headless:=true

world accepts a short name (see WORLDS), a file in sim/worlds/, or a path
to any .sdf / .world file.
"""

import os
import re
from pathlib import Path

from ament_index_python.packages import PackageNotFoundError, get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, OpaqueFunction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch_ros.actions import Node

SIM_DIR = Path(__file__).resolve().parent.parent
CUSTOM_WORLDS = SIM_DIR / 'worlds'

# Short world name -> (package, path inside package share, default x, default y).
# package None means a world bundled with Gazebo itself.
WORLDS = {
    'empty': (None, 'empty.sdf', 0.0, 0.0),
    'tb3_empty': ('turtlebot3_gazebo', 'worlds/empty_world.world', 0.0, 0.0),
    'house': ('turtlebot3_gazebo', 'worlds/turtlebot3_house.world', -2.0, -0.5),
    'turtlebot3_world': ('turtlebot3_gazebo', 'worlds/turtlebot3_world.world', -2.0, -0.5),
    'dqn_stage1': ('turtlebot3_gazebo', 'worlds/turtlebot3_dqn_stage1.world', 0.0, 0.0),
    'dqn_stage2': ('turtlebot3_gazebo', 'worlds/turtlebot3_dqn_stage2.world', 0.0, 0.0),
    'dqn_stage3': ('turtlebot3_gazebo', 'worlds/turtlebot3_dqn_stage3.world', 0.0, 0.0),
    'dqn_stage4': ('turtlebot3_gazebo', 'worlds/turtlebot3_dqn_stage4.world', 0.0, 0.0),
    'warehouse': ('turtlebot4_gz_bringup', 'worlds/warehouse.sdf', 0.0, 0.0),
    'depot': ('turtlebot4_gz_bringup', 'worlds/depot.sdf', 0.0, 0.0),
    'maze': ('turtlebot4_gz_bringup', 'worlds/maze.sdf', 0.0, 0.0),
}

ROBOT_MODELS = {
    'none': [''],
    'turtlebot3': ['waffle', 'waffle_pi', 'burger'],
    'turtlebot4': ['standard', 'lite'],
}

ROBOT_PACKAGES = {
    'turtlebot3': 'turtlebot3_gazebo',
    'turtlebot4': 'turtlebot4_gz_bringup',
}


def share(package):
    try:
        return Path(get_package_share_directory(package))
    except PackageNotFoundError:
        return None


def require_share(package, why):
    path = share(package)
    if path is None:
        raise RuntimeError(f'Package {package} is required for {why} but is not installed.')
    return path


def resolve_world(world):
    """Return (gz world argument, world name inside the SDF, default x, default y)."""
    path = Path(os.path.expanduser(world))
    if path.suffix in ('.sdf', '.world') and path.is_file():
        return str(path.resolve()), sdf_world_name(path), 0.0, 0.0

    for suffix in ('.sdf', '.world'):
        custom = CUSTOM_WORLDS / f'{world}{suffix}'
        if custom.is_file():
            return str(custom), sdf_world_name(custom), 0.0, 0.0

    if world not in WORLDS:
        raise RuntimeError(
            f"Unknown world '{world}'. Known: {', '.join(WORLDS)}, "
            f'files in {CUSTOM_WORLDS}, or a path to an .sdf/.world file.')

    package, relpath, x, y = WORLDS[world]
    if package is None:
        return relpath, Path(relpath).stem, x, y

    full = require_share(package, f"world '{world}'") / relpath
    return str(full), sdf_world_name(full), x, y


def sdf_world_name(path):
    match = re.search(r"<world\s+name\s*=\s*['\"]([^'\"]+)['\"]", path.read_text(errors='ignore'))
    return match.group(1) if match else 'default'


def append_env_path(name, *paths):
    current = [p for p in os.environ.get(name, '').split(':') if p]
    for p in paths:
        if p and str(p) not in current:
            current.append(str(p))
    os.environ[name] = ':'.join(current)


def gz_sim(gz_args):
    ros_gz_sim = require_share('ros_gz_sim', 'Gazebo')
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(str(ros_gz_sim / 'launch' / 'gz_sim.launch.py')),
        launch_arguments={'gz_args': gz_args, 'on_exit_shutdown': 'true'}.items(),
    )


def include(package, launch_file, **launch_args):
    path = require_share(package, launch_file) / 'launch' / launch_file
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(str(path)),
        launch_arguments={k: str(v) for k, v in launch_args.items()}.items(),
    )


def turtlebot3_actions(model, x, y):
    # Upstream launch files read the model from the environment at load time.
    os.environ['TURTLEBOT3_MODEL'] = model
    return [
        include('turtlebot3_gazebo', 'robot_state_publisher.launch.py', use_sim_time='true'),
        # Also bridges /clock.
        include('turtlebot3_gazebo', 'spawn_turtlebot3.launch.py', x_pose=x, y_pose=y),
    ]


def turtlebot4_actions(model, world_name, x, y, yaw):
    return [
        include(
            'turtlebot4_gz_bringup', 'turtlebot4_spawn.launch.py',
            world=world_name, model=model, x=x, y=y, yaw=yaw),
        Node(
            package='ros_gz_bridge', executable='parameter_bridge', name='clock_bridge',
            output='screen', arguments=['/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock']),
    ]


def setup_resource_paths():
    tb3 = share('turtlebot3_gazebo')
    if tb3:
        append_env_path('GZ_SIM_RESOURCE_PATH', tb3 / 'models')

    tb4 = share('turtlebot4_gz_bringup')
    if tb4:
        append_env_path(
            'GZ_SIM_RESOURCE_PATH',
            tb4 / 'worlds',
            *(p.parent for p in map(share, (
                'irobot_create_gz_bringup', 'turtlebot4_description', 'irobot_create_description',
            )) if p))
        append_env_path(
            'GZ_GUI_PLUGIN_PATH',
            *(p / 'lib' for p in map(share, (
                'turtlebot4_gz_gui_plugins', 'irobot_create_gz_plugins',
            )) if p))

    if CUSTOM_WORLDS.is_dir():
        append_env_path('GZ_SIM_RESOURCE_PATH', CUSTOM_WORLDS)


def launch_setup(context):
    cfg = {name: context.launch_configurations[name] for name in (
        'robot', 'model', 'world', 'headless', 'x', 'y', 'yaw', 'verbosity')}

    robot = cfg['robot']
    if robot not in ROBOT_MODELS:
        raise RuntimeError(f"Unknown robot '{robot}'. Known: {', '.join(ROBOT_MODELS)}")

    model = cfg['model'] or ROBOT_MODELS[robot][0]
    if model not in ROBOT_MODELS[robot]:
        raise RuntimeError(
            f"Unknown {robot} model '{model}'. Known: {', '.join(ROBOT_MODELS[robot])}")

    if robot in ROBOT_PACKAGES:
        require_share(ROBOT_PACKAGES[robot], f'robot {robot}')

    setup_resource_paths()

    world_arg, world_name, default_x, default_y = resolve_world(cfg['world'])
    x = cfg['x'] or default_x
    y = cfg['y'] or default_y
    headless = cfg['headless'].lower() in ('true', '1', 'yes')
    verbosity = cfg['verbosity']

    actions = [gz_sim(f'-r -s -v{verbosity} {world_arg}')]

    if not headless:
        gui_args = f'-g -v{verbosity}'
        if robot == 'turtlebot4':
            gui_config = share('turtlebot4_gz_bringup') / 'gui' / model / 'gui.config'
            if gui_config.is_file():
                gui_args += f' --gui-config {gui_config}'
        actions.append(gz_sim(gui_args))

    if robot == 'turtlebot3':
        actions += turtlebot3_actions(model, x, y)
    elif robot == 'turtlebot4':
        actions += turtlebot4_actions(model, world_name, x, y, cfg['yaw'])
    else:
        actions.append(Node(
            package='ros_gz_bridge', executable='parameter_bridge', name='clock_bridge',
            output='screen', arguments=['/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock']))

    print(f'[sim] robot={robot} model={model or "-"} world={world_arg} '
          f'pose=({x}, {y}) headless={headless}')

    return actions


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument(
            'robot', default_value='turtlebot3', choices=list(ROBOT_MODELS),
            description='Robot to spawn'),
        DeclareLaunchArgument(
            'model', default_value='',
            description='Robot variant (turtlebot3: waffle|waffle_pi|burger, '
                        'turtlebot4: standard|lite); empty = robot default'),
        DeclareLaunchArgument(
            'world', default_value='empty',
            description='World name, sim/worlds/<name>.sdf, or path to .sdf/.world'),
        DeclareLaunchArgument(
            'headless', default_value='false', description='Run without the Gazebo GUI'),
        DeclareLaunchArgument('x', default_value='', description='Spawn x (empty = world default)'),
        DeclareLaunchArgument('y', default_value='', description='Spawn y (empty = world default)'),
        DeclareLaunchArgument('yaw', default_value='0.0', description='Spawn yaw (turtlebot4 only)'),
        DeclareLaunchArgument('verbosity', default_value='2', description='Gazebo log verbosity 0-4'),
        OpaqueFunction(function=launch_setup),
    ])
