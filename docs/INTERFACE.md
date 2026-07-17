# Robot interface & fleet integration contract

This is the boundary between **"the robot"** (this simulation today, the real rover later)
and everything else in the fleet. Code on the Pi 5 / Jetson must only use what is listed
here; anything else is internal to the sim and will not exist on the real robot.

The robot is deliberately minimal, matching the real hardware plan:

- a **4-wheel mecanum base** (drive + wheel odometry), and
- a **RealSense D555-style RGBD camera with built-in IMU** — the only exteroceptive sensor.

There is **no lidar** and **no separate body IMU**. All mapping, localization, and
navigation intelligence lives *off* the robot:

| Where | What runs there | Consumes from the robot | Provides back |
|---|---|---|---|
| **This laptop (sim)** / real rover later | Gazebo world + robot model + `mecanum_drive_controller` — nothing else | `/mecanum_drive_controller/cmd_vel` | all sensor topics below |
| **Jetson Orin** | Visual SLAM (cuVSLAM or RTABMap), nvblox 3D mapping, **Nav2**, YOLO, speech | `/cam_1/*` (color, depth, IMU), `/mecanum_drive_controller/odom`, `/tf` | `map→odom` TF, Nav2 actions, velocity commands |
| **Pi 5** | LangGraph brain (reasoning), discovery server, micro-ROS agent | Nav2 actions on the Jetson, robot status | goals, behaviors |
| **Mac Mini** | LLM server (llama.cpp) | — | — |

## Topics the robot provides

| Topic | Type | Rate (sim time) | Notes |
|---|---|---|---|
| `/cam_1/color/image_raw` | `sensor_msgs/Image` | 15 Hz | RGB, 424×240, frame `cam_1_depth_optical_frame` (single gz RGBD sensor) |
| `/cam_1/color/camera_info` | `sensor_msgs/CameraInfo` | with image | intrinsics |
| `/cam_1/depth/image_rect_raw` | `sensor_msgs/Image` | 15 Hz | depth, 32FC1 meters, 0.05–8 m, frame `cam_1_depth_optical_frame` — nvblox input |
| `/cam_1/depth/camera_info` | `sensor_msgs/CameraInfo` | with image | depth intrinsics (same sensor as color) |
| `/cam_1/depth/color/points` | `sensor_msgs/PointCloud2` | 15 Hz | RGBD point cloud, camera frame |
| `/cam_1/imu` | `sensor_msgs/Imu` | 200 Hz | **camera's built-in IMU**, frame `cam_1_imu_optical_frame` — mirrors realsense-ros with `unite_imu_method` set. Sim IMU is noise/bias-free |
| `/mecanum_drive_controller/odom` | `nav_msgs/Odometry` | 50 Hz | wheel odometry, `odom` → `base_footprint` |
| `/joint_states`, `/tf`, `/tf_static` | — | — | standard state broadcasting |
| `/clock` | `rosgraph_msgs/Clock` | — | **sim only.** Every off-robot node consuming sim data must run `use_sim_time:=true` |

Topic names mirror the RealSense D555 driver so Jetson perception configs work unchanged
against sim and real camera — no remapping.

## Topics the robot consumes

| Topic | Type | Notes |
|---|---|---|
| `/mecanum_drive_controller/cmd_vel` | `geometry_msgs/TwistStamped` | **Stamped**, not plain Twist. Omnidirectional: `linear.x`, `linear.y`, `angular.z` all honored. ~±0.5 m/s, ±1.0 rad/s sensible limits |

This is the **only** command input. Nav2 on the Jetson must be configured to emit
`TwistStamped` on this topic (Jazzy Nav2: `enable_stamped_cmd_vel: true` on
`controller_server`/`velocity_smoother`, remap `cmd_vel` →
`/mecanum_drive_controller/cmd_vel`), or run a small restamping relay on the Jetson.

## Frames (REP-105) and who owns which transform

```
map → odom → base_footprint → base_link → cam_1_link → cam_1_color_optical_frame
                                                     → cam_1_depth_optical_frame
                                                     → cam_1_imu_frame → cam_1_imu_optical_frame
```

| Transform | Owner |
|---|---|
| `odom → base_footprint` | **the robot** — wheel odometry via `mecanum_drive_controller` (`enable_odom_tf:=true`, the fleet default) |
| `map → odom` | **the Jetson** — cuVSLAM / RTABMap / whatever SLAM is active. If the visual SLAM insists on owning `odom → base*` itself, start the sim with `enable_odom_tf:=false` and let it |
| everything right of `base_footprint` | `robot_state_publisher` from the URDF (static) |

The camera is mounted at `0.105 0 0.05` on `base_link`, pitched **down 0.50 rad**; get the
camera pose from TF, never hardcode it.

## Jetson pipeline integration notes

- **nvblox**: feed `/cam_1/depth/image_rect_raw` + `/cam_1/depth/camera_info` (+ color if
  wanted). Pose from TF. Verified end-to-end against this sim 2026-07-06.
- **RTABMap (RGB-D mode)**: rgb + registered depth + camera_info + external odom
  (`/mecanum_drive_controller/odom` or its own VO). Works from the D555-style topics as-is.
- **cuVSLAM (Isaac ROS Visual SLAM)**: prefers stereo IR pairs, which the sim does not
  render — use mono+IMU mode (`/cam_1/color/image_raw` + `/cam_1/imu`) or choose RTABMap
  against the sim and cuVSLAM only on real hardware.
- **`use_sim_time:=true` on every Jetson node** when running against the sim (they get
  `/clock` over DDS); `false` against the real rover. This is the #1 silent-failure gotcha
  (TF extrapolation errors, empty message filters).
- The sim IMU is ideal (no noise, no bias); don't tune VIO noise parameters against it.
- House world runs ≈ 0.1× real time on this laptop's iGPU; never calibrate wall-clock
  timings against the sim.

## Multi-machine setup (Fast DDS Discovery Server)

The fleet does not rely on multicast discovery. A Fast DDS Discovery Server runs on the Pi5
(`langrobo-discovery.service`, port 11811); every machine joins it by mDNS name. Full design:
Pi5 `~/ros2_ws/NETWORKING.md`.

On this laptop, `fleet_sim.sh start` joins automatically when the Pi5 resolves. For a manual
launch, source first (pins IPv4 — mDNS prefers IPv6 and the server is UDPv4-only, which
fails silently):

```bash
source src/rover_sim/rover_bringup/scripts/fleet_env.sh
```

| Machine | Role | mDNS name | wifi IP (dhcp, don't hardcode) |
|---|---|---|---|
| This laptop | robot stand-in (this repo) | hostname `rakhi24` | 192.168.1.12 |
| Pi 5 | LangGraph brain (`pi5_ros2_ws` → `~/ros2_ws`) | `rakhi24-desktop.local` | 192.168.1.16 |
| Jetson Orin | perception + Nav2 (`speech_vision` → `~/robot`) | `rakhi-jetson.local` | 192.168.1.15 |

`ROS_DOMAIN_ID=0` everywhere. Verify links by **echoing a continuously published topic**
(e.g. `/cam_1/imu` while the sim runs) — `ros2 node list` through the discovery server
returns empty on this Jazzy build even when pub/sub works (verified 2026-07-06).

## Smoke-testing the contract

```bash
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh start     # on the laptop (or via Pi5 fleet.sh sim)
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh status    # "2/2 active controllers" = drive ready

ros2 topic hz /cam_1/depth/image_rect_raw   # ~15 Hz (sim time)
ros2 topic hz /cam_1/imu                    # ~200 Hz (sim time)
ros2 topic pub -r 10 /mecanum_drive_controller/cmd_vel geometry_msgs/msg/TwistStamped \
  "{header: {frame_id: base_link}, twist: {linear: {x: 0.2}}}"   # robot creeps forward
ros2 topic echo /mecanum_drive_controller/odom --once            # pose changes
```

Teleop: `ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/mecanum_drive_controller/cmd_vel -p stamped:=true`

## Real-robot swap

The whole point of the sim: when the physical rover exists, it must publish/consume exactly
the tables above and nothing on the Pi 5 / Jetson changes. Checklist:
[REAL_ROBOT_SWAP.md](REAL_ROBOT_SWAP.md).
