import json
import math
from typing import Optional

import rclpy
from geometry_msgs.msg import Twist
from nav_msgs.msg import Odometry
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image, LaserScan
from std_msgs.msg import String


ACTIONS = {"FORWARD", "BACKWARD", "LEFT", "RIGHT", "STOP"}


def quaternion_to_yaw(x: float, y: float, z: float, w: float) -> float:
    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    return math.atan2(siny_cosp, cosy_cosp)


def finite_min(values, fallback: float) -> float:
    finite = [value for value in values if math.isfinite(value)]
    return min(finite) if finite else fallback


class VLABridge(Node):
    def __init__(self) -> None:
        super().__init__("vla_bridge")

        self.declare_parameter("image_topic", "/camera/image_raw")
        self.declare_parameter("scan_topic", "/scan")
        self.declare_parameter("odom_topic", "/vla_bench/fused/odom")
        self.declare_parameter("instruction_topic", "/vla_bench/vla/instruction")
        self.declare_parameter("action_topic", "/vla_bench/vla/action")
        self.declare_parameter("observation_topic", "/vla_bench/vla/observation")
        self.declare_parameter("cmd_vel_topic", "/cmd_vel")
        self.declare_parameter("publish_rate", 5.0)
        self.declare_parameter("linear_speed", 0.20)
        self.declare_parameter("angular_speed", 0.60)
        self.declare_parameter("action_timeout", 0.75)
        self.declare_parameter("stop_distance", 0.45)

        self.image_topic = self.get_parameter("image_topic").value
        self.scan_topic = self.get_parameter("scan_topic").value
        self.odom_topic = self.get_parameter("odom_topic").value
        self.instruction_topic = self.get_parameter("instruction_topic").value
        self.action_topic = self.get_parameter("action_topic").value
        self.observation_topic = self.get_parameter("observation_topic").value
        self.cmd_vel_topic = self.get_parameter("cmd_vel_topic").value
        publish_rate = float(self.get_parameter("publish_rate").value)
        self.linear_speed = float(self.get_parameter("linear_speed").value)
        self.angular_speed = float(self.get_parameter("angular_speed").value)
        self.action_timeout = float(self.get_parameter("action_timeout").value)
        self.stop_distance = float(self.get_parameter("stop_distance").value)

        self.latest_image: Optional[Image] = None
        self.latest_scan: Optional[LaserScan] = None
        self.latest_odom: Optional[Odometry] = None
        self.instruction = ""
        self.last_action = "STOP"
        self.action_deadline_ns = 0

        self.create_subscription(
            Image, self.image_topic, self._on_image, qos_profile_sensor_data
        )
        self.create_subscription(
            LaserScan, self.scan_topic, self._on_scan, qos_profile_sensor_data
        )
        self.create_subscription(
            Odometry, self.odom_topic, self._on_odom, qos_profile_sensor_data
        )
        self.create_subscription(String, self.instruction_topic, self._on_instruction, 10)
        self.create_subscription(String, self.action_topic, self._on_action, 10)

        self.observation_pub = self.create_publisher(String, self.observation_topic, 10)
        self.cmd_pub = self.create_publisher(Twist, self.cmd_vel_topic, 10)

        self.create_timer(1.0 / max(0.5, publish_rate), self._publish_observation)
        self.create_timer(0.05, self._watchdog)

        self.get_logger().info(
            "VLA bridge ready: observation=%s action=%s image=%s"
            % (self.observation_topic, self.action_topic, self.image_topic)
        )

    def _on_image(self, msg: Image) -> None:
        self.latest_image = msg

    def _on_scan(self, msg: LaserScan) -> None:
        self.latest_scan = msg

    def _on_odom(self, msg: Odometry) -> None:
        self.latest_odom = msg

    def _on_instruction(self, msg: String) -> None:
        self.instruction = msg.data.strip()

    def _scan_sector_min(self, center: float, half_width: float) -> Optional[float]:
        scan = self.latest_scan
        if scan is None or not scan.ranges:
            return None

        values = []
        angle = scan.angle_min
        for distance in scan.ranges:
            wrapped = math.atan2(math.sin(angle - center), math.cos(angle - center))
            if abs(wrapped) <= half_width:
                values.append(distance)
            angle += scan.angle_increment

        if not values:
            return None
        return finite_min(values, scan.range_max)

    def _front_clear(self) -> bool:
        front = self._scan_sector_min(0.0, math.radians(20.0))
        return front is not None and front >= self.stop_distance

    def _twist_for(self, action: str) -> Twist:
        msg = Twist()
        if action == "FORWARD":
            msg.linear.x = abs(self.linear_speed)
        elif action == "BACKWARD":
            msg.linear.x = -abs(self.linear_speed)
        elif action == "LEFT":
            msg.angular.z = abs(self.angular_speed)
        elif action == "RIGHT":
            msg.angular.z = -abs(self.angular_speed)
        return msg

    def _on_action(self, msg: String) -> None:
        action = msg.data.strip().upper()
        if action not in ACTIONS:
            self.get_logger().warning(
                "Rejected unknown VLA action %r; expected %s"
                % (msg.data, sorted(ACTIONS))
            )
            action = "STOP"

        if action == "FORWARD" and not self._front_clear():
            self.get_logger().warning(
                "Safety guard converted FORWARD to STOP: obstacle or missing scan"
            )
            action = "STOP"

        self.last_action = action
        self.cmd_pub.publish(self._twist_for(action))

        now_ns = self.get_clock().now().nanoseconds
        self.action_deadline_ns = now_ns + int(max(0.0, self.action_timeout) * 1e9)

    def _watchdog(self) -> None:
        if self.last_action == "STOP":
            return
        if self.get_clock().now().nanoseconds >= self.action_deadline_ns:
            self.last_action = "STOP"
            self.cmd_pub.publish(Twist())

    def _publish_observation(self) -> None:
        if self.latest_image is None or self.latest_scan is None or self.latest_odom is None:
            return

        odom = self.latest_odom
        q = odom.pose.pose.orientation
        front = self._scan_sector_min(0.0, math.radians(20.0))
        left = self._scan_sector_min(math.pi / 2.0, math.radians(35.0))
        right = self._scan_sector_min(-math.pi / 2.0, math.radians(35.0))

        payload = {
            "schema": "vla_bench.observation.v1",
            "instruction": self.instruction,
            "image": {
                "topic": self.image_topic,
                "stamp": {
                    "sec": self.latest_image.header.stamp.sec,
                    "nanosec": self.latest_image.header.stamp.nanosec,
                },
                "frame_id": self.latest_image.header.frame_id,
                "width": self.latest_image.width,
                "height": self.latest_image.height,
                "encoding": self.latest_image.encoding,
            },
            "pose": {
                "frame_id": odom.header.frame_id,
                "x": odom.pose.pose.position.x,
                "y": odom.pose.pose.position.y,
                "yaw": quaternion_to_yaw(q.x, q.y, q.z, q.w),
                "linear_x": odom.twist.twist.linear.x,
                "angular_z": odom.twist.twist.angular.z,
            },
            "lidar": {
                "front_min_m": front,
                "left_min_m": left,
                "right_min_m": right,
                "stop_distance_m": self.stop_distance,
            },
            "last_action": self.last_action,
        }

        msg = String()
        msg.data = json.dumps(payload, separators=(",", ":"), allow_nan=False)
        self.observation_pub.publish(msg)


def main() -> None:
    rclpy.init()
    node = VLABridge()
    try:
        rclpy.spin(node)
    finally:
        node.cmd_pub.publish(Twist())
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
