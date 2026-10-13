#include <algorithm>
#include <functional>
#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/joint_state.hpp>
#include <nav_msgs/msg/odometry.hpp>

// Configuration for turtlebot3 waffle
constexpr double WHEEL_RADIUS = 0.033;     // metres
constexpr double WHEEL_SEPARATION = 0.287; // metres

class WheelOdometryNode : public rclcpp::Node
{
    public:
    WheelOdometryNode() : Node("wheel_odometry_node")
    {
        subscription_ = create_subscription<sensor_msgs::msg::JointState>(
            "/joint_states",
            rclcpp::SensorDataQoS(),
            std::bind(
                &WheelOdometryNode::jointStateCallback,
                this,
                std::placeholders::_1));
        RCLCPP_INFO(get_logger(), "Wheel odometry node started");

        odom_publisher_ =
            create_publisher<nav_msgs::msg::Odometry>(
                "/vla_bench/wheel/odom_estimated",
                10);
    }

    private:
    void jointStateCallback(const sensor_msgs::msg::JointState::SharedPtr msg)
    {
        const auto left = std::find(
            msg->name.begin(),
            msg->name.end(),
            "wheel_left_joint");

        const auto right = std::find(
            msg->name.begin(),
            msg->name.end(),
            "wheel_right_joint");

        if (left == msg->name.end() || right == msg->name.end()) {
            RCLCPP_WARN(get_logger(), "Joint names not found in joint state message");
            return;
        }

        const auto left_index = std::distance(msg->name.begin(), left);
        const auto right_index = std::distance(msg->name.begin(), right);

        if (msg->position.size() <= static_cast<std::size_t>(std::max(left_index, right_index))) {
            RCLCPP_WARN(get_logger(), "Joint state message does not contain enough position data");
            return;
        }

        double phi_left = msg->position[left_index];
        double phi_right = msg->position[right_index];

        if (!initialized_)
        {
            previous_left_ = phi_left;
            previous_right_ = phi_right;
            initialized_ = true;
            return;
        }

        double delta_left = phi_left - previous_left_;
        double delta_right = phi_right - previous_right_;

        // Important: store CURRENT positions, not deltas
        previous_left_ = phi_left;
        previous_right_ = phi_right;

        double distance_left = delta_left * WHEEL_RADIUS;
        double distance_right = delta_right * WHEEL_RADIUS;

        double delta_distance =
            (distance_left + distance_right) / 2.0;

        double delta_yaw =
            (distance_right - distance_left) / WHEEL_SEPARATION;

        double mid_yaw = yaw_ + delta_yaw / 2.0;
        x_ += delta_distance * std::cos(mid_yaw);
        y_ += delta_distance * std::sin(mid_yaw);
        yaw_ += delta_yaw;

        yaw_ = std::atan2(std::sin(yaw_), std::cos(yaw_));

        nav_msgs::msg::Odometry odom;

        odom.header.stamp = msg->header.stamp;
        odom.header.frame_id = "wheel_odom";

        odom.child_frame_id = "base_footprint";

        odom.pose.pose.position.x = x_;
        odom.pose.pose.position.y = y_;
        odom.pose.pose.position.z = 0.0;

        odom.pose.pose.orientation.x = 0.0;
        odom.pose.pose.orientation.y = 0.0;
        odom.pose.pose.orientation.z = std::sin(yaw_ / 2.0);
        odom.pose.pose.orientation.w = std::cos(yaw_ / 2.0);

        if (msg->velocity.size() > static_cast<std::size_t>(std::max(left_index, right_index)))
        {
            double velocity_left =
                msg->velocity[left_index] * WHEEL_RADIUS;

            double velocity_right =
                msg->velocity[right_index] * WHEEL_RADIUS;

            odom.twist.twist.linear.x =
                (velocity_left + velocity_right) / 2.0;

            odom.twist.twist.angular.z =
                (velocity_right - velocity_left) / WHEEL_SEPARATION;
        }

        odom.pose.covariance[0] = 0.01;  // x variance, m²
        odom.pose.covariance[7] = 0.01;  // y variance, m²
        odom.pose.covariance[35] = 0.05; // yaw variance, rad²

        odom_publisher_->publish(odom);

        // RCLCPP_INFO_THROTTLE(
        //     get_logger(),
        //     *get_clock(),
        //     500,
        //     "x=%.3f y=%.3f yaw=%.3f",
        //     x_, y_, yaw_);
    }

    rclcpp::Subscription<sensor_msgs::msg::JointState>::SharedPtr subscription_;
    rclcpp::Publisher<nav_msgs::msg::Odometry>::SharedPtr odom_publisher_;
    double previous_left_;
    double previous_right_;
    bool initialized_ = false;

    double x_ = 0.0;
    double y_ = 0.0;
    double yaw_ = 0.0;
};

int main(int argc, char **argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<WheelOdometryNode>());
    rclcpp::shutdown();
    return 0;
}