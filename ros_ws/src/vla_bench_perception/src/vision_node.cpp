#include <memory>

#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/image.hpp>
#include <sensor_msgs/image_encodings.hpp>

#include <cv_bridge/cv_bridge.hpp>
#include <opencv2/opencv.hpp>

class VisionNode : public rclcpp::Node
{
public:
    VisionNode() : Node("vision_node")
    {
        image_sub_ = create_subscription<sensor_msgs::msg::Image>(
            "/camera/image_raw", 10,
            std::bind(&VisionNode::imageCallback, this, std::placeholders::_1));

    image_pub_ = create_publisher<sensor_msgs::msg::Image>("/vla_bench/vision/debug_image", 10);

    RCLCPP_INFO(this->get_logger(), "Vision node started.");
}

private: 
void imageCallback(const sensor_msgs::msg::Image::SharedPtr msg)
{
    cv_bridge::CvImagePtr cv_ptr;
    try
    {
        cv_ptr = cv_bridge::toCvCopy(msg, sensor_msgs::image_encodings::BGR8);
    }
    catch (cv_bridge::Exception& e)
    {
        RCLCPP_ERROR(this->get_logger(), "cv_bridge exception: %s", e.what());
        return;
    }
    
    int width = cv_ptr->image.cols;
    int height = cv_ptr->image.rows;
    cv::Rect roi(width / 3, height / 3, width / 3 * 2, height / 3 * 2);
    cv::Mat cropped_image = cv_ptr->image(roi);

    cv::Mat gray;
    cv::Mat blurred;
    cv::Mat edges;

    cv::cvtColor(
        cropped_image, gray, cv::COLOR_BGR2GRAY
    );

    cv::GaussianBlur(
        gray, blurred, cv::Size(5, 5), 0
    );

    cv::Canny(
        blurred,
        edges, 50, 150
    );

    cv::Mat debug;

    cv::cvtColor(
        edges, debug, cv::COLOR_GRAY2BGR
    );
    
    auto output_msg = cv_bridge::CvImage(
        msg->header, sensor_msgs::image_encodings::BGR8, debug
    ).toImageMsg();

    image_pub_->publish(*output_msg);
}

    rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr image_sub_;
    rclcpp::Publisher<sensor_msgs::msg::Image>::SharedPtr image_pub_;
};

int main(int argc, char* argv[])
{
    rclcpp::init(argc, argv);
    auto node = std::make_shared<VisionNode>();
    rclcpp::spin(node);
    rclcpp::shutdown();
    return 0;
}
