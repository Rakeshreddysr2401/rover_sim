# rover_sim

Gazebo simulation of a mecanum-wheel rover (Yahboom ROSMASTER X3 class) for ROS 2 Jazzy.

This repository is the **simulation stand-in for the real rover** in a multi-machine robot
system. It provides the robot, its sensors, and changeable indoor environments so the
higher-level stacks (LangGraph brain on the Pi 5, Isaac ROS perception on the Jetson) can be
developed and tested before the real robot exists. Everything the sim exposes — topics, types,
frames — is the contract the real robot must satisfy later. See
[docs/INTERFACE.md](docs/INTERFACE.md).

## System context

```
┌────────────┐   /voice/*    ┌─────────────┐   /cmd_vel, nav2 actions   ┌──────────────────┐
│ Jetson Orin│ ────────────► │  Pi 5 brain │ ─────────────────────────► │  THIS LAPTOP     │
│ speech +   │               │  LangGraph  │ ◄───────────────────────── │  Gazebo sim of   │
│ Isaac ROS  │ ◄──────────── │  planning   │   /scan /odom /camera/*    │  the rover       │
└────────────┘   images      └─────────────┘                            └──────────────────┘
      ▲                                                                        │
      └────────────────── later: replaced by the real rover ◄─────────────────┘
```

## Packages

| Package | Purpose |
|---|---|
| `rover_description` | URDF/XACRO of the rover (mecanum base, RGBD camera, lidar, IMU) |
| `rover_gazebo` | Worlds (house, cafe, empty), local model library, ros_gz bridge config |
| `rover_bringup` | Top-level launch files and convenience scripts |
| `rover_navigation` | Nav2 config (omni motion model), SLAM (slam_toolbox), pre-made maps |
| `rover_localization` | EKF sensor fusion (robot_localization: wheel odom + IMU) |
| `rover_docking` | Nav2 docking server + AprilTag dock pose detection (optional) |
| `rover_msgs` | Custom actions/services |
| `rover_system_tests` | Motion test nodes (square drive, etc.) |
| `mecanum_drive_controller` | ros2_control controller for the 4 mecanum wheels |

## Quick start

```bash
cd /workspace/ros2_ws
colcon build --symlink-install && source install/setup.bash

# Sim only (Gazebo GUI + RViz), house world by default:
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_gazebo.sh

# Sim + Nav2 with the pre-made house map:
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_navigation.sh

# Sim + Nav2 building the map live with SLAM:
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_navigation.sh slam

# Other worlds:  WORLD=cafe ./src/rover_sim/rover_bringup/scripts/rosmaster_x3_gazebo.sh
```

Teleop test: `ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/mecanum_drive_controller/cmd_vel -p stamped:=true`

Send a nav goal from code: see `rover_navigation/scripts/nav_to_pose.py`.

## Environments

- `house.world` — multi-room home (hallway, bedroom, living room with TV + TV cabinet,
  kitchen) built from the AWS RoboMaker residential model set, plus small findable objects
  (coke can, mustard bottle, …). All models are local to `rover_gazebo/models` — no downloads.
- `cafe.world` — cafe with tables and counter.
- `empty.world` — empty plane, runs at ~1.0 real-time factor; use for controller/kinematics work.

**Performance note (no discrete GPU):** the fully furnished `house.world` runs at roughly 0.1
real-time factor on integrated graphics. Everything still works — sensor rates are correct in
sim time and Nav2 uses sim time — it is just slower than wall clock. Use `empty.world` or
`cafe.world` when you don't need the furniture.

## Changing the robot or the environment

- New environment: drop a world file in `rover_gazebo/worlds/`, reuse models from
  `rover_gazebo/models/`, then `WORLD=<name>` (expects `<name>.world`, and
  `<name>_world_map.yaml` in `rover_navigation/maps` for map-based navigation).
- Robot variant: `rover_description/urdf/robots/rosmaster_x3.urdf.xacro` composes the base,
  wheels, and sensors from `urdf/mech/` and `urdf/sensors/`. Add a new robot file there and
  pass `robot_name:=<variant>` (controller config lives in
  `rover_description/config/<variant>/`).

## Swapping in the real robot

The entire point of this repo. See [docs/REAL_ROBOT_SWAP.md](docs/REAL_ROBOT_SWAP.md).

## Credits

Robot model, controller, and world assets adapted from
[automaticaddison/yahboom_rosmaster](https://github.com/automaticaddison/yahboom_rosmaster)
(BSD-3-Clause, per-package LICENSE files retained) and the AWS RoboMaker model sets.
