# Robot interface contract

This is the boundary between "the robot" (this simulation today, the real rover later) and
everything else (Pi 5 brain, Jetson perception). Code on the Pi 5 / Jetson must only use what
is listed here; anything else is internal to the sim and will not exist on the real robot.

## Topics the robot provides

| Topic | Type | Rate (sim time) | Notes |
|---|---|---|---|
| `/scan` | `sensor_msgs/LaserScan` | 10 Hz | 2D lidar, frame `laser_frame` |
| `/imu/data` | `sensor_msgs/Imu` | 15 Hz | frame `imu_frame` |
| `/cam_1/color/image_raw` | `sensor_msgs/Image` | 15 Hz | RGB image |
| `/cam_1/color/camera_info` | `sensor_msgs/CameraInfo` | with image | intrinsics |
| `/cam_1/depth/image_rect_raw` | `sensor_msgs/Image` | 15 Hz | depth, 32FC1 meters, frame `cam_1_depth_optical_frame`, 8 m range — nvblox input; names mirror RealSense D555 |
| `/cam_1/depth/camera_info` | `sensor_msgs/CameraInfo` | with image | depth intrinsics (same sensor as color) |
| `/cam_1/depth/color/points` | `sensor_msgs/PointCloud2` | 15 Hz | RGBD point cloud, camera frame |
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
(`laser_frame`, `cam_1_link`, `cam_1_depth_optical_frame`, `imu_frame`).
`map→odom` exists only when SLAM/AMCL is running.

## Multi-machine setup (Fast DDS Discovery Server)

The fleet does not rely on multicast discovery. A Fast DDS Discovery Server runs on the Pi5
(`langrobo-discovery.service`, port 11811); every machine joins it by mDNS name. Full design:
Pi5 `~/ros2_ws/NETWORKING.md`.

On this laptop, before launching the sim for fleet-connected work:

```bash
export ROS_DISCOVERY_SERVER=rakhi24-desktop.local:11811
```

| Machine | Role | mDNS name | wifi IP (dhcp, don't hardcode) |
|---|---|---|---|
| This laptop | Gazebo sim (this repo) | — | 192.168.1.12 |
| Pi 5 | LangGraph brain (`pi5_ros2_ws` → `~/ros2_ws`) | `rakhi24-desktop.local` | 192.168.1.16 |
| Jetson Orin | speech + Isaac ROS (`speech_vision` → `~/robot`) | `rakhi-jetson.local` | 192.168.1.15 |

`ROS_DOMAIN_ID=0` everywhere. Verify links by **echoing a continuously published topic**
(e.g. `/scan` while the sim runs) — `ros2 node list` through the discovery server returns
empty on this Jazzy build even when pub/sub works (verified 2026-07-06).

### Known integration gaps (as of 2026-07-07)

- Pi 5 brain's `navigate_to_pose` tool currently reports "no server" after a 10 s wait
  (nav2 was phase-2). With this sim's nav stack running and `ROS_DISCOVERY_SERVER` set on
  the laptop, that action server is now real — end-to-end test pending.
- Isaac ROS pipelines (nvblox, visual SLAM, YOLOv8) on the Jetson consume RealSense-style
  topics; the sim publishes D555-style names natively (`/cam_1/depth/image_rect_raw` +
  `/cam_1/depth/camera_info`) so no remapping should be needed — end-to-end test pending.
- The house world runs ≈ 0.1× real time on this laptop's iGPU; time-sensitive tuning
  (controller gains, VAD-style timings) should not be calibrated against sim wall-clock.
