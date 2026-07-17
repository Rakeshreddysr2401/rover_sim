# rover_sim

Gazebo simulation of a mecanum-wheel rover (Yahboom ROSMASTER X3 class) for ROS 2 Jazzy.

This repository is the **simulation stand-in for the real rover** in a multi-machine robot
system, and deliberately nothing more: it provides the **4-wheel mecanum robot**, its **one
sensor — a RealSense D555-style RGBD camera with built-in IMU** — and changeable indoor
environments. All intelligence runs off-robot: visual SLAM (cuVSLAM/RTABMap), nvblox 3D
mapping, and Nav2 on the Jetson; LangGraph reasoning on the Pi 5. Everything the sim
exposes — topics, types, frames — is the contract the real robot must satisfy later. See
[docs/INTERFACE.md](docs/INTERFACE.md).

## System context

```
┌─────────────────────┐   nav2 goals   ┌─────────────┐
│  Jetson Orin        │ ◄───────────── │  Pi 5 brain │
│  cuVSLAM/RTABMap,   │                │  LangGraph  │
│  nvblox, Nav2,      │                │  reasoning  │
│  YOLO, speech       │                └─────────────┘
└──────┬──────▲───────┘
       │      │  /cam_1/color/*  /cam_1/depth/*  /cam_1/imu  /odom  /tf
  cmd_vel     │
       ▼      │
┌─────────────┴────────┐
│  THIS LAPTOP         │   ◄── later: replaced by the real rover
│  Gazebo sim: rover + │       (same topics, same frames)
│  D555 cam + world    │
└──────────────────────┘
```

## Packages

| Package | Purpose |
|---|---|
| `rover_description` | URDF/XACRO of the rover (mecanum base + D555-style RGBD camera with built-in IMU) |
| `rover_gazebo` | Worlds (house, cafe, empty), local model library, ros_gz bridge config |
| `rover_bringup` | Launch files and convenience scripts (`fleet_sim.sh`, `rosmaster_x3_gazebo.sh`) |
| `mecanum_drive_controller` | ros2_control controller for the 4 mecanum wheels (+ wheel odometry) |
| `rover_msgs` | Custom actions/services used by the test nodes |
| `rover_system_tests` | Motion test nodes (square drive, etc.) |

No Nav2/SLAM/EKF packages here — mapping and navigation are the Jetson's job
(see [docs/INTERFACE.md](docs/INTERFACE.md) for the split).

## Quick start

```bash
cd /workspace/ros2_ws
colcon build --symlink-install && source install/setup.bash

# Gazebo GUI + RViz, house world by default:
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_gazebo.sh

# Other worlds:
WORLD=cafe ./src/rover_sim/rover_bringup/scripts/rosmaster_x3_gazebo.sh

# As a fleet member (headless-capable, joins the Pi5 discovery server when up):
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh start
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh status   # "2/2 active controllers" = drive ready
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh stop
```

Teleop test: `ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/mecanum_drive_controller/cmd_vel -p stamped:=true`

## Environments

- `house.world` — multi-room home (hallway, bedroom, living room with TV + TV cabinet,
  kitchen) built from the AWS RoboMaker residential model set, plus small findable objects
  (coke can, mustard bottle, …). All models are local to `rover_gazebo/models` — no downloads.
- `cafe.world` — cafe with tables and counter.
- `empty.world` — empty plane, runs at ~1.0 real-time factor; use for controller/kinematics work.

**Performance note (no discrete GPU):** the fully furnished `house.world` runs at roughly 0.1
real-time factor on integrated graphics. Everything still works — sensor rates are correct in
sim time — it is just slower than wall clock. Use `empty.world` or `cafe.world` when you
don't need the furniture.

## Changing the robot or the environment

- New environment: drop a world file in `rover_gazebo/worlds/`, reuse models from
  `rover_gazebo/models/`, then `WORLD=<name>` (expects `<name>.world`).
- Robot variant: `rover_description/urdf/robots/rosmaster_x3.urdf.xacro` composes the base,
  wheels, and camera from `urdf/mech/` and `urdf/sensors/`. Add a new robot file there and
  pass `robot_name:=<variant>` (controller config lives in
  `rover_description/config/<variant>/`).

## Swapping in the real robot

The entire point of this repo. See [docs/REAL_ROBOT_SWAP.md](docs/REAL_ROBOT_SWAP.md).

## Credits

Robot model, controller, and world assets adapted from
[automaticaddison/yahboom_rosmaster](https://github.com/automaticaddison/yahboom_rosmaster)
(BSD-3-Clause, per-package LICENSE files retained) and the AWS RoboMaker model sets.
