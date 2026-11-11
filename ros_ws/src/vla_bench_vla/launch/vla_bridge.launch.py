from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package="vla_bench_vla",
            executable="bridge",
            name="vla_bridge",
            output="screen",
            parameters=[{
                "image_topic": "/camera/image_raw",
                "scan_topic": "/scan",
                "odom_topic": "/vla_bench/fused/odom",
                "instruction_topic": "/vla_bench/vla/instruction",
                "action_topic": "/vla_bench/vla/action",
                "observation_topic": "/vla_bench/vla/observation",
                "cmd_vel_topic": "/cmd_vel",
                "publish_rate": 5.0,
                "linear_speed": 0.20,
                "angular_speed": 0.60,
                "action_timeout": 0.75,
                "stop_distance": 0.45,
            }],
        )
    ])
