# Robot interface contract

This is the boundary between "the robot" (this simulation today, the real rover later) and
everything else (Pi 5 brain, Jetson perception). Code on the Pi 5 / Jetson must only use what
is listed here; anything else is internal to the sim and will not exist on the real robot.

## Topics the robot provides

| Topic | Type | Rate (sim time) | Notes |
|---|---|---|---|
| `/scan` | `sensor_msgs/LaserScan` | 10 Hz | 2D lidar, frame `laser_frame` |
| `/imu/data` | `sensor_msgs/Imu` | 15 Hz | frame `imu_frame` |
| `/cam_1/color/image_raw` | `sensor_msgs/Image` | 2 Hz | RGB image |
| `/cam_1/color/camera_info` | `sensor_msgs/CameraInfo` | with image | intrinsics |
| `/cam_1/depth/color/points` | `sensor_msgs/PointCloud2` | 2 Hz | RGBD point cloud, camera frame |
| `/mecanum_drive_controller/odom` | `nav_msgs/Odometry` | 50 Hz | wheel odometry |
| `/odometry/filtered` | `nav_msgs/Odometry` | 30 Hz | EKF-fused odom (only when nav stack is up) |
| `/joint_states`, `/tf`, `/tf_static` | — | — | standard state broadcasting |

## Topics the robot consumes

| Topic | Type | Notes |
|---|---|---|
| `/mecanum_drive_controller/cmd_vel` | `geometry_msgs/TwistStamped` | **Stamped**, not plain Twist. Omnidirectional: `linear.x`, `linear.y`, `angular.z` all honored |
| `/cmd_vel` | `geometry_msgs/Twist` | Only when Nav2 stack is running (relay node restamps to the controller topic) |

## Actions (when navigation stack is running)

| Action | Type | Use |
|---|---|---|
| `/navigate_to_pose` | `nav2_msgs/action/NavigateToPose` | "go to (x, y, yaw) in map frame" — the primary entry point for the Pi 5 brain |
| `/navigate_through_poses` | `nav2_msgs/action/NavigateThroughPoses` | waypoint following |
| `/dock_robot`, `/undock_robot` | `opennav_docking_msgs` | optional docking |

`rover_navigation/scripts/nav_to_pose.py` is a worked example of sending a goal.

## Frames (REP-105)

`map` → `odom` → `base_footprint` → `base_link` → sensor frames
(`laser_frame`, `cam_1_link`, `cam_1_depth_frame`, `imu_frame`).
`map→odom` exists only when SLAM/AMCL is running.

## Multi-machine setup

All machines must share the same `ROS_DOMAIN_ID` (default **0** everywhere today) and be on
the same LAN for DDS discovery.

| Machine | Role | LAN wifi IP | Ethernet/robot net |
|---|---|---|---|
| This laptop | Gazebo sim (this repo) | 192.168.1.12 (dhcp — verify) | — |
| Pi 5 | LangGraph brain (`pi5_ros2_ws`) | 192.168.1.16 | 192.168.2.10 |
| Jetson Orin | speech + Isaac ROS (`speech_vision`) | 192.168.1.15 | 192.168.2.20 |

Quick cross-machine check: `ros2 topic list` on the Pi 5 should show `/scan` while the sim
runs here.

### Known integration gaps (as of 2026-07-06)

- Pi 5 `ai_agent/agent_node.py` listens on `voice_text`, but the Jetson STT publishes
  `/voice/user_input` — the Pi 5 side needs to be updated to match the Jetson.
- Pi 5 brain does not yet publish `cmd_vel` or call `navigate_to_pose`; when it does, use the
  action (preferred) or `/cmd_vel` while Nav2 is up.
- Isaac ROS pipelines (nvblox, visual SLAM, YOLOv8) on the Jetson expect RealSense-style
  input; the sim camera topics (`/cam_1/color/*`, `/cam_1/depth/color/points`) are the
  equivalents to remap.
