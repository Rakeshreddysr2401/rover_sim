# rover_sim

Gazebo (gz-sim 8 / Harmonic) simulation that **impersonates the real "Rakhi" home rover** for
ROS 2 Jazzy, so the rest of the fleet can be developed and tested without the physical robot.

The sim publishes the *exact* real-robot contract — a RealSense D555 on `/camera/camera0/*`
with wall-clock stamps and captured real intrinsics, and a 4-wheel skid-steer base driven
over `/cmd_vel` through a byte-accurate port of the ESP32 firmware. The Jetson (visual SLAM,
nvblox, Nav2) and Pi 5 (LangGraph reasoning) stacks run **unchanged** and cannot tell they
are in simulation. Everything they touch is defined in [docs/INTERFACE.md](docs/INTERFACE.md).

## System context

```
┌─────────────────────┐   nav2 goals   ┌─────────────┐
│  Jetson Orin        │ ◄───────────── │  Pi 5 brain │
│  RTAB-Map/cuVSLAM,  │                │  LangGraph  │
│  nvblox, Nav2,      │                │  reasoning  │
│  YOLO, speech       │                └─────────────┘
└──────┬──────▲───────┘
  /cmd_vel    │  /camera/camera0/*  (wall-clock, captured intrinsics)  /tf
       ▼      │
┌─────────────┴────────┐   config/hardware = sim │ real
│  robot               │   ┌── sim:  THIS LAPTOP — gz sim + rover_contract
│  (D555 + skid-steer) │ ──┤
│                      │   └── real: the physical rover (same topics/frames)
└──────────────────────┘
```

## Packages

| Package | Purpose |
|---|---|
| `rover_gazebo` | The gz world (`langrobo_home`) + the rover model (D555-matched sensor rig, 4-wheel skid-steer) |
| `rover_contract` | The D555/ESP32 impersonation layer: `restamper` (C++) + `contract_bridge.py` + captured `d555_contract/` data |
| `rover_bringup` | `fleet_sim.sh` (the 4-stage pipeline) + `fleet_env.sh` |

No ROS navigation/description packages — the robot is just sensors + drive; mapping and nav
are the Jetson's job. See [docs/INTERFACE.md](docs/INTERFACE.md) for the split.

## Quick start

```bash
cd /workspace/ros2_ws
colcon build --symlink-install && source install/setup.bash

./src/rover_sim/rover_bringup/scripts/fleet_sim.sh start   # headless 4-stage pipeline
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh status  # {"mode":"sim", ...} = up
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh gui      # optional Gazebo GUI
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh stop
```

Drive it: `ros2 topic pub -r 20 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.2}}"`
(stops 0.5 s after you Ctrl-C — the firmware watchdog).

## The world

`langrobo_home.sdf` — a 6×5 m room with a doorway, furniture, a "bottle" nav target, and
lots of colored wall/floor patches. The patches are **not decoration**: RTAB-Map tracks
visual features on the grayscale infra1 stream, and featureless sim walls would kill visual
odometry exactly like a blank real wall. Runs headless at **RTF ≈ 1.0** (wall-clock stamp
parity requires real-time). The old furnished house/cafe worlds and the AWS model library are
still under `rover_gazebo/{worlds,models}` as assets, but `fleet_sim.sh` doesn't use them.

## Swapping in the real robot

A single `config/hardware` flip on the Jetson — nothing else changes. See
[docs/REAL_ROBOT_SWAP.md](docs/REAL_ROBOT_SWAP.md).

## Credits

Earlier mecanum robot/world assets were adapted from
[automaticaddison/yahboom_rosmaster](https://github.com/automaticaddison/yahboom_rosmaster)
(BSD-3-Clause); the current parity model, world, and impersonation bridge are LangRobo's own.
