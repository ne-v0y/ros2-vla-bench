#include <memory>
#include <functional>
#include <cmath>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/image.hpp>
#include <sensor_msgs/msg/laser_scan.hpp>
#include <nav_msgs/msg/odometry.hpp>

#include <tf2_ros/buffer.h>
#include <tf2_ros/transform_listener.h>
#include <tf2/time.hpp>
#include <tf2/exceptions.hpp>

class PerceptionNode : public rclcpp::Node
{
public:
    PerceptionNode() : Node("perception_node")
    {
        tf_buffer_ = std::make_unique<tf2_ros::Buffer>(
            get_clock());

        tf_listener_ =
            std::make_shared<tf2_ros::TransformListener>(
                *tf_buffer_);

        camera_sub_ =
            create_subscription<sensor_msgs::msg::Image>(
                "/vla_bench/camera/image_raw",
                rclcpp::SensorDataQoS(),
                [this](sensor_msgs::msg::Image::SharedPtr msg)
                {
                    latest_image_ = msg;
                });

        odom_sub_ =
            create_subscription<nav_msgs::msg::Odometry>(
                "/odom",
                rclcpp::SensorDataQoS(),
                [this](nav_msgs::msg::Odometry::SharedPtr msg)
                {
                    latest_odom_ = msg;
                });

        scan_sub_ =
            create_subscription<sensor_msgs::msg::LaserScan>(
                "/scan",
                rclcpp::SensorDataQoS(),
                std::bind(
                    &PerceptionNode::scanCallback,
                    this,
                    std::placeholders::_1));
    }

private:
    void scanCallback(
        sensor_msgs::msg::LaserScan::SharedPtr scan)
    {
        if (!latest_image_ || !latest_odom_)
        {
            return;
        }

        try
        {
            auto transform = tf_buffer_->lookupTransform(
                "base_link",
                scan->header.frame_id,
                tf2::TimePointZero);

            double camera_age = std::abs(
                (
                    rclcpp::Time(scan->header.stamp) -
                    rclcpp::Time(latest_image_->header.stamp))
                    .seconds());

            RCLCPP_INFO_THROTTLE(
                get_logger(),
                *get_clock(),
                1000,
                "camera=%ux%u | pose=(%.2f, %.2f) | "
                "lidar_x=%.3f | camera_skew=%.3fs",
                latest_image_->width,
                latest_image_->height,
                latest_odom_->pose.pose.position.x,
                latest_odom_->pose.pose.position.y,
                transform.transform.translation.x,
                camera_age);
        }
        catch (const tf2::TransformException &ex)
        {
            RCLCPP_WARN_THROTTLE(
                get_logger(),
                *get_clock(),
                1000,
                "TF unavailable: %s",
                ex.what());
        }
    }

    sensor_msgs::msg::Image::SharedPtr latest_image_;
    nav_msgs::msg::Odometry::SharedPtr latest_odom_;

    rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr
        camera_sub_;

    rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr
        odom_sub_;

    rclcpp::Subscription<sensor_msgs::msg::LaserScan>::SharedPtr
        scan_sub_;

    std::unique_ptr<tf2_ros::Buffer> tf_buffer_;
    std::shared_ptr<tf2_ros::TransformListener> tf_listener_;
};

int main(int argc, char **argv)
{
    rclcpp::init(argc, argv);
    rclcpp::spin(std::make_shared<PerceptionNode>());
    rclcpp::shutdown();
    return 0;
}