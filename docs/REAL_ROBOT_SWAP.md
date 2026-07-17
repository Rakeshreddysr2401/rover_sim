# Swapping the simulation for the real rover

The Pi 5 / Jetson code must not change when the real robot arrives. Everything they touch is
defined in [INTERFACE.md](INTERFACE.md); this document is the checklist for making the real
rover satisfy that contract.

The real rover is intentionally simple — matching what the sim models:

- 4-wheel mecanum base (ESP32 + micro-ROS to the Pi5's agent, or a ros2_control hardware
  interface)
- one RealSense D555 (RGBD + built-in IMU) — the only exteroceptive sensor

## What gets replaced

| Sim component | Real-robot replacement |
|---|---|
| Gazebo physics + `gz_ros2_control` | Motor driver: ESP32 via micro-ROS (UDP 8888 to the Pi5 agent) or a ros2_control hardware interface running `mecanum_drive_controller` |
| Simulated RGBD cam + IMU → `/cam_1/*`, `/cam_1/imu` | `realsense-ros` driver, `camera_name:=cam_1`, depth aligned, `unite_imu_method:=2` (linear_interpolation) so the IMU comes out united on `/cam_1/imu` |
| `rover_gazebo` worlds | The actual house |
| `/clock` + `use_sim_time:=true` everywhere | Wall clock — `use_sim_time:=false` on every machine |

Suggested real camera bringup (run wherever the D555 is plugged in — Jetson):

```bash
ros2 launch realsense2_camera rs_launch.py \
  camera_name:=cam_1 camera_namespace:=/ \
  align_depth.enable:=true unite_imu_method:=2 \
  enable_gyro:=true enable_accel:=true \
  depth_module.depth_profile:=424x240x15 rgb_camera.color_profile:=424x240x15
```

Then verify the topic names match INTERFACE.md exactly (`ros2 topic list | grep cam_1`);
adjust profiles upward once the Jetson pipelines are happy.

## What stays identical

- All topic names, types, frames — this is the contract
- `rover_description` URDF minus the gazebo plugins (update wheel radius / separation and
  the measured camera mount pose; keep frame names)
- `mecanum_drive_controller` + `rover_description/config/*/ros2_controllers.yaml` if the
  real base uses ros2_control — only the hardware plugin line changes from
  `gz_ros2_control/GazeboSimSystem` to your hardware interface
- Everything on the Jetson (SLAM, nvblox, Nav2) and the Pi 5 (brain) — by construction

## Procedure

1. Bring up the real base; verify `/mecanum_drive_controller/cmd_vel` (TwistStamped) moves
   it and `/mecanum_drive_controller/odom` responds (or remap the driver's topics to these
   names). Confirm the `odom → base_footprint` TF is broadcast.
2. Bring up the D555 with the launch above; verify frames match the URDF
   (`ros2 run tf2_tools view_frames`) and `/cam_1/imu` streams (~200 Hz).
3. Publish the URDF with `robot_state_publisher` (`use_gazebo:=false`,
   `use_sim_time:=false`) so the static camera TF exists.
4. Flip every Jetson/Pi5 node to `use_sim_time:=false`.
5. Point the Jetson pipelines at the robot — nothing on their side changes except VIO/IMU
   noise parameters, which must be re-tuned on the real (noisy) IMU.

## Launch-file rule that makes this work

Keep "robot" launch files free of sim-only nodes. Gazebo, the ros_gz bridge, and the spawner
live only in `rover_gazebo`; `rover_bringup` composes either the sim or the real robot under
the same downstream stack.
