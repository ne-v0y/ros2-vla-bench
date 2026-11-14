cmake_minimum_required(VERSION 3.8)

project(vla_bench_perception)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# find dependencies
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(cv_bridge REQUIRED)
find_package(OpenCV REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(tf2 REQUIRED)
find_package(tf2_ros REQUIRED)

if(BUILD_TESTING)
  find_package(ament_lint_auto REQUIRED)
  # the following line skips the linter which checks for copyrights
  # comment the line when a copyright and license is added to all source files
  set(ament_cmake_copyright_FOUND TRUE)
  # the following line skips cpplint (only works in a git repo)
  # comment the line when this package is in a git repo and when
  # a copyright and license is added to all source files
  set(ament_cmake_cpplint_FOUND TRUE)
  ament_lint_auto_find_test_dependencies()
endif()

add_executable(vision_node src/vision_node.cpp)
ament_target_dependencies(vision_node rclcpp sensor_msgs cv_bridge)
target_link_libraries(vision_node ${OpenCV_LIBS})

add_executable(laser_node src/laser_node.cpp)
ament_target_dependencies(laser_node rclcpp sensor_msgs)

add_executable(odom_node src/odom_node.cpp)
ament_target_dependencies(odom_node rclcpp nav_msgs)

add_executable(wheel_odometry_node src/wheel_odometry_node.cpp)

ament_target_dependencies(
  wheel_odometry_node
  rclcpp
  sensor_msgs
  nav_msgs
)

add_executable(
  perception_node
  src/perception_node.cpp
)

ament_target_dependencies(
  perception_node
  rclcpp
  sensor_msgs
  nav_msgs
  tf2
  tf2_ros
)

install(
  TARGETS
    vision_node
    laser_node
    perception_node
    odom_node
    wheel_odometry_node
  DESTINATION lib/${PROJECT_NAME}
)

install(
  DIRECTORY launch config
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
