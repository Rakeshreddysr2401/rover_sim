# Robot interface & fleet integration contract

This is the boundary between **"the robot"** and the rest of the fleet (Pi 5 brain,
Jetson perception). The sim's whole job is to **impersonate the real rover** so exactly that
the Jetson/Pi 5 stack runs unchanged and cannot tell it is in simulation:

- a **4-wheel skid-steer base** driven over plain `/cmd_vel`, through a byte-accurate port of
  the ESP32 firmware (PWM deadband, watchdog), and
- a **RealSense D555** publishing `/camera/camera0/*` with **wall-clock stamps** and the
  **captured real intrinsics + static frame tree**.

The contract below is the *real robot's* contract, captured from real hardware — the sim
conforms to it, not the other way round. All mapping/localization/navigation lives on the
Jetson; reasoning on the Pi 5.

| Where | What runs there | Consumes from the robot | Provides back |
|---|---|---|---|
| **This laptop (sim)** / real rover | gz sim + `rover_contract` impersonation — no ROS nav logic | `/cmd_vel` | the `/camera/camera0/*` topics + TF below |
| **Jetson Orin** | Visual SLAM (RTAB-Map / cuVSLAM), nvblox, **Nav2**, YOLO, speech | `/camera/camera0/*`, `/tf` | `map→odom`, Nav2 actions, `/cmd_vel` |
| **Pi 5** | LangGraph brain (reasoning), micro-ROS agent to the real ESP32 | Nav2 actions on the Jetson | goals, behaviors |

## How the sim produces the contract (4-stage pipeline)

```
gz sim (headless, RTF 1.0)                     world + rover model, internal /rover_sim/* topics
   → ros_gz parameter_bridge                   gz → ROS on internal names
   → rover_contract/restamper  (C++)           /rover_sim/{infra1,color,depth} → /camera/camera0/*
                                               wall-clock stamps, depth 32FC1 m → 16UC1 mm, paired camera_info
   → rover_contract/contract_bridge.py         /rover_sim/imu → /camera/camera0/motion/sample (optical axes)
                                               /cmd_vel → ESP32 firmware emulation → gz DiffDrive
                                               captured real /tf_static, /rover_sim/status marker
```

`./rover_bringup/scripts/fleet_sim.sh start` runs all four stages headless.

## Topics the robot provides

| Topic | Type | Rate | Notes |
|---|---|---|---|
| `/camera/camera0/color/image_raw` | `sensor_msgs/Image` | 15 Hz | RGB8, 896×504, frame `camera0_color_optical_frame` |
| `/camera/camera0/color/camera_info` | `sensor_msgs/CameraInfo` | with image | same stamp as its image (paired like the real driver) |
| `/camera/camera0/infra1/image_rect_raw` | `sensor_msgs/Image` | 15 Hz | mono8 (L8), the feature stream for visual SLAM |
| `/camera/camera0/infra1/camera_info` | `sensor_msgs/CameraInfo` | with image | |
| `/camera/camera0/depth/image_rect_raw` | `sensor_msgs/Image` | 15 Hz | **16UC1 millimetres, 0 = invalid** (RealSense convention), frame `camera0_depth_optical_frame` — nvblox/RTAB-Map input |
| `/camera/camera0/depth/camera_info` | `sensor_msgs/CameraInfo` | with image | |
| `/camera/camera0/motion/sample` | `sensor_msgs/Imu` | 200 Hz | camera IMU, frame `camera0_motion_optical_frame`, `orientation_covariance[0] = -1` (no orientation, like the D555) |
| `/tf_static` | `tf2_msgs/TFMessage` | latched | the **captured real** `camera0_*` frame tree |
| `/rover_sim/status` | `std_msgs/String` | 1 Hz | JSON `{"mode":"sim", ...}` — the ONLY topic that betrays the sim; a real-mode marker replaces it on hardware |

All stamps are **wall-clock** — consumers run with `use_sim_time:=false`, exactly as against
the real camera. There is no `/clock`.

## Topics the robot consumes

| Topic | Type | Notes |
|---|---|---|
| `/cmd_vel` | `geometry_msgs/Twist` | plain Twist. Passed through the ESP32 firmware emulation before it reaches the wheels — see below |

### Firmware emulation (what `/cmd_vel` actually does)

`contract_bridge.py` is a byte-accurate port of `rover_firmware.ino` (keep it in sync with
the Pi 5 copy). Consequences the Jetson's controller must expect — identical on sim and real:

- **PWM deadband floor** (`PWM_MIN = 130/255`): any wheel command above the dead-stick
  threshold jumps to ≥51 % duty. A requested `vx = 0.03 m/s` actually drives ≈ `0.168 m/s`.
  There is no smooth low-speed regime — tune Nav2 velocity limits around this.
- **Dead-stick** (`|v| ≤ 0.02`): wheel parked.
- **Full-scale** `0.30 m/s` linear, `2.0 rad/s` the firmware's (uncalibrated) angular
  normalizer; **track 0.24 m**.
- **Watchdog** `0.5 s`: stop publishing `/cmd_vel` and the wheels halt. Nav2 must stream
  commands continuously.

## Frames (REP-105) and who owns which transform

```
map → odom → base_link → camera0_link → camera0_color_optical_frame
                                      → camera0_infra1_optical_frame
                                      → camera0_depth_optical_frame
                                      → camera0_motion_optical_frame
```

| Transform | Owner |
|---|---|
| `camera0_link` and everything below | **the robot** — captured real `/tf_static` (published by `contract_bridge.py`) |
| `map → odom`, `odom → base_link` | **the Jetson** — the visual SLAM (RTAB-Map / cuVSLAM). The sim publishes **no** odometry; SLAM is the sole pose source, matching the real deployment where there are no wheel encoders |
| `base_link → camera0_link` | provided by the Jetson/robot bringup (`run_robot_tf.sh` on real; the sim mount is baked into the model at `x 0.10, z 0.25`) |

### Accepted sim/real divergences (documented, not bugs)

- **2 driven→now 4-wheel skid-steer**, frictionless-caster physics gone; sim still turns
  slightly easier than the real skid-steer.
- **camera_info principal point** is gz-centered (`cx≈448`) vs the real off-center
  (`cx≈440.17`); focal length matches (hfov derived from the real `fx≈450.26`). Real values
  are in `rover_contract/d555_contract/` for reference.
- Rendered images are undistortion-free; color `camera_info` still carries the real
  distortion coefficients.
- Sim IMU is noise-free (depth carries a small gaussian); don't tune VIO noise against it.

## Networking

The parity pipeline runs on **plain ROS 2 domain-0 discovery** (`ROS_DOMAIN_ID=0`,
multicast), verified 2026-07-17 — `fleet_sim.sh` explicitly `unset`s
`ROS_DISCOVERY_SERVER`/`FASTRTPS_DEFAULT_PROFILES_FILE`. This differs from the
discovery-server scheme in the Pi5 `NETWORKING.md`; **reconcile the two before changing
either** (open question — see CLAUDE.md).

| Machine | mDNS name | wifi IP (dhcp) |
|---|---|---|
| This laptop (robot stand-in) | `rakhi24` | 192.168.1.12 |
| Pi 5 (brain) | `rakhi24-desktop.local` | 192.168.1.16 |
| Jetson Orin (perception + Nav2) | `rakhi-jetson.local` | 192.168.1.15 |

## Smoke-testing the contract

```bash
./rover_bringup/scripts/fleet_sim.sh start
./rover_bringup/scripts/fleet_sim.sh status          # {"mode":"sim", "counts":{...}}

ros2 topic hz /camera/camera0/depth/image_rect_raw   # ~15 Hz
ros2 topic echo /camera/camera0/depth/image_rect_raw --once --field encoding   # 16UC1
ros2 topic echo /camera/camera0/motion/sample --once --field header.frame_id   # camera0_motion_optical_frame
ros2 topic pub -r 20 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.2}}"     # robot drives; stops 0.5s after Ctrl-C (watchdog)
./rover_bringup/scripts/fleet_sim.sh gui              # optional: attach a Gazebo GUI
```

On the Jetson: `echo sim > config/hardware && robot restart`, then `scripts/check_contract.sh`
must be as green as real mode.

## Real-robot swap

There is nothing to swap on the Jetson/Pi 5 side — that's the point. The checklist for
turning the real rover on instead of the sim: [REAL_ROBOT_SWAP.md](REAL_ROBOT_SWAP.md).
