cmake_minimum_required(VERSION 3.16)
project(rover_contract)
set(CMAKE_CXX_STANDARD 17)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)

# C++ image path: gz internal names -> contract names, wall stamps, 16UC1 depth
add_executable(restamper src/restamper.cpp)
target_link_libraries(restamper PUBLIC rclcpp::rclcpp ${sensor_msgs_TARGETS})
install(TARGETS restamper DESTINATION lib/${PROJECT_NAME})

# Python path: imu remap, firmware emulation, captured static TF, status marker
install(PROGRAMS scripts/contract_bridge.py DESTINATION lib/${PROJECT_NAME})

# Captured REAL D555 data (camera_infos + static frame tree). Never edit by
# hand — recapture from the real camera.
install(DIRECTORY d555_contract DESTINATION share/${PROJECT_NAME})

ament_package()
