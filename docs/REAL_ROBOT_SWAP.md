# Swapping the simulation for the real rover

The Pi 5 / Jetson code must not change when the real robot arrives. Everything they touch is
defined in [INTERFACE.md](INTERFACE.md); this document is the checklist for making the real
rover satisfy that contract.

## What gets replaced

| Sim component | Real-robot replacement |
|---|---|
| Gazebo physics + `gz_ros2_control` | Rover motor driver (ros2_control hardware interface, or the vendor driver bridged via micro-ROS) |
| Simulated lidar → `/scan` | Real lidar driver publishing `/scan` in `laser_frame` |
| Simulated RGBD cam → `/cam_1/*` | RealSense driver; remap its topics to `/cam_1/color/image_raw`, `/cam_1/color/camera_info`, `/cam_1/depth/color/points` |
| Simulated IMU → `/imu/data` | Real IMU driver |
| `rover_gazebo` worlds | The actual room |

## What stays identical

- `rover_description` URDF (update wheel radius / separation to measured values)
- `mecanum_drive_controller` + `rover_description/config/*/ros2_controllers.yaml` if you use
  ros2_control on the real base — only the hardware plugin line changes from
  `gz_ros2_control/GazeboSimSystem` to your hardware interface
- `rover_navigation` (Nav2 + slam_toolbox configs, maps made on the real robot)
- `rover_localization` EKF config
- All topic names, types, frames — this is the contract

## Procedure

1. Bring up the real base with its driver; verify `/mecanum_drive_controller/cmd_vel` moves it
   and `/mecanum_drive_controller/odom` responds (or remap the driver's topics to these names).
2. Bring up lidar/camera/IMU drivers; verify frames match the URDF (`ros2 run tf2_tools
   view_frames`).
3. Run `rover_bringup/launch/rosmaster_x3_navigation.launch.py` with
   `use_sim_time:=false`, `use_gazebo:=false`, SLAM on; drive around to build the room map.
4. Point the Pi 5 / Jetson at the robot — nothing on their side changes.

## Launch-file rule that makes this work

Keep "robot" launch files free of sim-only nodes. Gazebo, the ros_gz bridge, and the spawner
live only in `rover_gazebo`; `rover_bringup` composes either the sim or the real robot under
the same downstream stack.
