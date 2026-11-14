#include <algorithm>
#include <cmath>
#include <functional>
#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/joint_state.hpp>
#include <nav_msgs/msg/odometry.hpp>

class WheelOdometryNode : public rclcpp::Node
{
public:
    WheelOdometryNode() : Node("wheel_odometry_node")
    {
        wheel_radius_ = declare_parameter<double>("wheel_radius", 0.10);
        wheel_separation_ = declare_parameter<double>("wheel_separation", 0.40);
        left_joint_ = declare_parameter<std::string>("left_joint", "wheel_left_joint");
        right_joint_ = declare_parameter<std::string>("right_joint", "wheel_right_joint");
        joint_states_topic_ = declare_parameter<std::string>("joint_states_topic", "/joint_states");
        odom_topic_ = declare_parameter<std::string>(
            "odom_topic", "/vla_bench/wheel/odom_estimated");
        odom_frame_ = declare_parameter<std::string>("odom_frame", "wheel_odom");
        base_frame_ = declare_parameter<std::string>("base_frame", "base_link");

        if (wheel_radius_ <= 0.0 || wheel_separation_ <= 0.0) {
            throw std::runtime_error("wheel_radius and wheel_separation must be positive");
        }

        subscription_ = create_subscription<sensor_msgs::msg::JointState>(
            joint_states_topic_,
            rclcpp::SensorDataQoS(),
            std::bind(&WheelOdometryNode::jointStateCallback, this, std::placeholders::_1));

        odom_publisher_ = create_publisher<nav_msgs::msg::Odometry>(odom_topic_, 10);

        RCLCPP_INFO(
            get_logger(),
            "Wheel odometry: radius=%.3f separation=%.3f joints=(%s,%s) -> %s",
            wheel_radius_, wheel_separation_,
            left_joint_.c_str(), right_joint_.c_str(), odom_topic_.c_str());
    }

private:
    void jointStateCallback(const sensor_msgs::msg::JointState::SharedPtr msg)
    {
        const auto left = std::find(msg->name.begin(), msg->name.end(), left_joint_);
        const auto right = std::find(msg->name.begin(), msg->name.end(), right_joint_);

        if (left == msg->name.end() || right == msg->name.end()) {
            RCLCPP_WARN_THROTTLE(
                get_logger(), *get_clock(), 2000,
                "Expected wheel joints '%s' and '%s' were not found",
                left_joint_.c_str(), right_joint_.c_str());
            return;
        }

        const auto left_index = std::distance(msg->name.begin(), left);
        const auto right_index = std::distance(msg->name.begin(), right);
        const auto max_index = static_cast<std::size_t>(std::max(left_index, right_index));

        if (msg->position.size() <= max_index) {
            RCLCPP_WARN_THROTTLE(
                get_logger(), *get_clock(), 2000,
                "Joint state does not contain enough position data");
            return;
        }

        const double phi_left = msg->position[left_index];
        const double phi_right = msg->position[right_index];

        if (!initialized_) {
            previous_left_ = phi_left;
            previous_right_ = phi_right;
            initialized_ = true;
            return;
        }

        const double delta_left = phi_left - previous_left_;
        const double delta_right = phi_right - previous_right_;
        previous_left_ = phi_left;
        previous_right_ = phi_right;

        const double distance_left = delta_left * wheel_radius_;
        const double distance_right = delta_right * wheel_radius_;
        const double delta_distance = (distance_left + distance_right) / 2.0;
        const double delta_yaw = (distance_right - distance_left) / wheel_separation_;

        const double mid_yaw = yaw_ + delta_yaw / 2.0;
        x_ += delta_distance * std::cos(mid_yaw);
        y_ += delta_distance * std::sin(mid_yaw);
        yaw_ += delta_yaw;
        yaw_ = std::atan2(std::sin(yaw_), std::cos(yaw_));

        nav_msgs::msg::Odometry odom;
        odom.header.stamp = msg->header.stamp;
        odom.header.frame_id = odom_frame_;
        odom.child_frame_id = base_frame_;
        odom.pose.pose.position.x = x_;
        odom.pose.pose.position.y = y_;
        odom.pose.pose.orientation.z = std::sin(yaw_ / 2.0);
        odom.pose.pose.orientation.w = std::cos(yaw_ / 2.0);

        if (msg->velocity.size() > max_index) {
            const double velocity_left = msg->velocity[left_index] * wheel_radius_;
            const double velocity_right = msg->velocity[right_index] * wheel_radius_;
            odom.twist.twist.linear.x = (velocity_left + velocity_right) / 2.0;
            odom.twist.twist.angular.z =
                (velocity_right - velocity_left) / wheel_separation_;
        }

        // Intentionally non-zero so robot_localization can weight this source.
        odom.pose.covariance[0] = 0.02;
        odom.pose.covariance[7] = 0.02;
        odom.pose.covariance[35] = 0.08;
        odom.twist.covariance[0] = 0.03;
        odom.twist.covariance[35] = 0.08;

        odom_publisher_->publish(odom);
    }

    rclcpp::Subscription<sensor_msgs::msg::JointState>::SharedPtr subscription_;
    rclcpp::Publisher<nav_msgs::msg::Odometry>::SharedPtr odom_publisher_;

    double wheel_radius_;
    double wheel_separation_;
    std::string left_joint_;
    std::string right_joint_;
    std::string joint_states_topic_;
    std::string odom_topic_;
    std::string odom_frame_;
    std::string base_frame_;

    double previous_left_ = 0.0;
    double previous_right_ = 0.0;
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
