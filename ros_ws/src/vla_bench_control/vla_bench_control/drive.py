import argparse
import time

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node


COMMANDS = ("forward", "backward", "left", "right", "stop")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Send a short velocity command to a ROS 2 mobile robot."
    )
    parser.add_argument("command", choices=COMMANDS)
    parser.add_argument(
        "--linear",
        type=float,
        default=0.20,
        help="Absolute linear speed in m/s (default: 0.20)",
    )
    parser.add_argument(
        "--angular",
        type=float,
        default=0.60,
        help="Absolute angular speed in rad/s (default: 0.60)",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=1.0,
        help="How long to publish the command in seconds (default: 1.0)",
    )
    parser.add_argument(
        "--rate",
        type=float,
        default=10.0,
        help="Publish rate in Hz (default: 10)",
    )
    parser.add_argument(
        "--topic",
        default="/cmd_vel",
        help="Twist topic to publish to (default: /cmd_vel)",
    )
    return parser.parse_args()


def twist_for(command: str, linear: float, angular: float) -> Twist:
    msg = Twist()

    if command == "forward":
        msg.linear.x = abs(linear)
    elif command == "backward":
        msg.linear.x = -abs(linear)
    elif command == "left":
        msg.angular.z = abs(angular)
    elif command == "right":
        msg.angular.z = -abs(angular)

    return msg


class VelocityCommander(Node):
    def __init__(self, topic: str):
        super().__init__("vla_bench_velocity_commander")
        self.publisher = self.create_publisher(Twist, topic, 10)


def publish_for(
    node: VelocityCommander,
    message: Twist,
    duration: float,
    rate: float,
) -> None:
    duration = max(0.0, duration)
    rate = max(1.0, rate)
    interval = 1.0 / rate
    deadline = time.monotonic() + duration

    # Publish once immediately so very short commands still do something.
    node.publisher.publish(message)

    while rclpy.ok() and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.0)
        time.sleep(interval)
        node.publisher.publish(message)


def publish_stop(node: VelocityCommander) -> None:
    stop = Twist()
    # Publish more than once to make the final stop command less likely to be missed.
    for _ in range(3):
        node.publisher.publish(stop)
        rclpy.spin_once(node, timeout_sec=0.0)
        time.sleep(0.05)


def main():
    args = parse_args()

    if args.duration < 0:
        raise SystemExit("--duration must be >= 0")
    if args.linear < 0 or args.angular < 0:
        raise SystemExit("--linear and --angular must be >= 0")
    if args.rate <= 0:
        raise SystemExit("--rate must be > 0")

    rclpy.init()

    node = VelocityCommander(args.topic)
    command = twist_for(args.command, args.linear, args.angular)

    try:
        node.get_logger().info(
            f"command={args.command} topic={args.topic} "
            f"linear.x={command.linear.x:.3f} "
            f"angular.z={command.angular.z:.3f} "
            f"duration={args.duration:.2f}s"
        )
        publish_for(node, command, args.duration, args.rate)
    finally:
        publish_stop(node)
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
