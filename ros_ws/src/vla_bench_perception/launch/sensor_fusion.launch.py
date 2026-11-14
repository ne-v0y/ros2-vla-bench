from pathlib import Path

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    share = Path(get_package_share_directory("vla_bench_perception"))
    ekf_config = share / "config" / "ekf.yaml"

    return LaunchDescription([
        Node(
            package="vla_bench_perception",
            executable="wheel_odometry_node",
            name="wheel_odometry",
            output="screen",
            parameters=[{
                "wheel_radius": 0.10,
                "wheel_separation": 0.40,
                "left_joint": "wheel_left_joint",
                "right_joint": "wheel_right_joint",
                "base_frame": "base_link",
                "odom_frame": "wheel_odom",
            }],
        ),
        Node(
            package="robot_localization",
            executable="ekf_node",
            name="vla_bench_ekf",
            output="screen",
            parameters=[str(ekf_config)],
            remappings=[("odometry/filtered", "/vla_bench/fused/odom")],
        ),
    ])
