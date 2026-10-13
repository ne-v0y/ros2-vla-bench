#include <memory>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/laser_scan.hpp>

constexpr float PI = 3.14159265359f;

/**
 * @brief Normalizes an angle to the range [-π, π)
 * 
 * @param angle 
 * @return float 
 */
float normalizeAngle(float angle)
{
    return std::atan2(std::sin(angle), std::cos(angle));
}

float degToRad(float degrees)
{
    return degrees * PI / 180.0f;   
}

float minRangeInSector(
    const sensor_msgs::msg::LaserScan & scan, float min_angle, float max_angle) 
{
    float minimum = std::numeric_limits<float>::infinity();

    for (std::size_t i = 0; i < scan.ranges.size(); ++i) {
        float angle = scan.angle_min + i * scan.angle_increment;
        angle = normalizeAngle(angle);

        if (angle < min_angle || angle > max_angle) {
            continue;
        }
        float range = scan.ranges[i];
        if (!std::isfinite(range)) {
            continue;
        }
        
        if (range < scan.range_min || range > scan.range_max) {
            continue;
        }

        minimum = std::min(minimum, range);
    }
    return minimum;
}

class LaserNode : public rclcpp::Node
{
public:
    LaserNode()
        : Node("laser_node")
    {
        subscription_ =
            create_subscription<sensor_msgs::msg::LaserScan>(
                "/scan",
                rclcpp::SensorDataQoS(),
                std::bind(
                    &LaserNode::scanCallback,
                    this,
                    std::placeholders::_1));

        RCLCPP_INFO(get_logger(), "Laser node started");
    }

private:
    void scanCallback(
        const sensor_msgs::msg::LaserScan::SharedPtr msg)
    {
        float front = minRangeInSector(
            *msg,
            degToRad(-20.0f),
            degToRad(20.0f));

        float front_left = minRangeInSector(
            *msg,
            degToRad(20.0f),
            degToRad(60.0f));

        float left = minRangeInSector(
            *msg,
            degToRad(60.0f),
            degToRad(120.0f));

        float front_right = minRangeInSector(
            *msg,
            degToRad(-60.0f),
            degToRad(-20.0f));

        float right = minRangeInSector(
            *msg,
            degToRad(-120.0f),
            degToRad(-60.0f));

        RCLCPP_INFO(
            get_logger(),
            "L %.2f | FL %.2f | F %.2f | FR %.2f | R %.2f",
            left,
            front_left,
            front,
            front_right,
            right);
    }

    rclcpp::Subscription<
        sensor_msgs::msg::LaserScan>::SharedPtr subscription_;
};

int main(int argc, char **argv)
{
    rclcpp::init(argc, argv);

    auto node = std::make_shared<LaserNode>();

    rclcpp::spin(node);

    rclcpp::shutdown();

    return 0;
}