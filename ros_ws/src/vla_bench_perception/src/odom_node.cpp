#include <cmath>
#include <memory>

#include <rclcpp/rclcpp.hpp>
#include <nav_msgs/msg/odometry.hpp>

class OdomNode : public rclcpp::Node
{
public:
    OdomNode() : Node("odom_node")
    {
        subscription_ = create_subscription<nav_msgs::msg::Odometry>(
            "/odom",
            rclcpp::SensorDataQoS(),
            std::bind(
                &OdomNode::odomCallback, 
                this,
                std::placeholders::_1
            ));
            RCLCPP_INFO(get_logger(), "Odom node started");
        }

private:
    void odomCallback(const nav_msgs::msg::Odometry::SharedPtr msg)
    {
        double x = msg->pose.pose.position.x;
        double y = msg->pose.pose.position.y;
        double z = msg->pose.pose.position.z;

        const auto & q = msg -> pose.pose.orientation;

        RCLCPP_INFO(
            get_logger(),
            "x=%.2f y=%.2f q=(%.2f %.2f %.2f %.2f)",
            x,
            y,
            q.x,
            q.y,
            q.z,
            q.w);
    }

    rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr subscription_;
};

int main(int argc, char * argv[])
{
    rclcpp::init(argc, argv);
    auto node = std::make_shared<OdomNode>();
    rclcpp::spin(node);
    rclcpp::shutdown();
    return 0;
}