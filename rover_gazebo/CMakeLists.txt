cmake_minimum_required(VERSION 3.8)
project(rover_gazebo)

find_package(ament_cmake REQUIRED)

# Worlds + models only: the sim runs as plain `gz sim` (fleet_sim.sh), with
# rover_contract providing the ROS side of the pipeline.
install (
  DIRECTORY models worlds
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
