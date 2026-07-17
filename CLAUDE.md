# rover_sim — working notes

Sim that **impersonates the real mecanum rover** ("Rakhi" home robot fleet). ROS 2 Jazzy +
Gazebo (gz-sim 8 / Harmonic), Ubuntu 24.04. GitHub:
https://github.com/Rakeshreddysr2401/rover_sim. Workspace: `/workspace/ros2_ws` (HDD
partition; keep large artifacts — bags, maps, models — under `/workspace`, not the SSD home dir).

**Scope (major pivot 2026-07-17): hardware impersonation, not a generic robot sim.** The sim
publishes the *exact* real-robot contract — RealSense D555 on `/camera/camera0/*` with
wall-clock stamps + captured real intrinsics, 4-wheel skid-steer driven over `/cmd_vel`
through a byte-accurate ESP32 firmware port. The Jetson (RTAB-Map/cuVSLAM, nvblox, Nav2) and
Pi5 (LangGraph reasoning) run UNCHANGED and can't tell sim from real (`config/hardware=sim`
on the Jetson). Contract: `docs/INTERFACE.md`. This replaced an earlier `/cam_1/*` +
TwistStamped mecanum design (see git history / [[three-machine-nav-pipeline]]); the parity
implementation was merged in from `~/langrobo/rover_sim` — see [[langrobo-parity-sim-merge]].

## Build & run

```bash
cd /workspace/ros2_ws && colcon build --symlink-install && source install/setup.bash
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh start   # headless 4-stage pipeline
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh status  # {"mode":"sim",...} = up
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh gui     # attach a Gazebo GUI
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh stop
```

The 4 stages: `gz sim` (headless, RTF 1.0) → `ros_gz parameter_bridge` (internal
`/rover_sim/*`) → `rover_contract/restamper` (C++: contract names, wall stamps, depth
32FC1→16UC1) → `rover_contract/contract_bridge.py` (imu axes, `/cmd_vel` firmware emulation,
captured `/tf_static`, status marker). The parity pipeline uses `langrobo_home` only
(wall-clock parity needs RTF≈1.0); the old furnished house/cafe worlds + AWS model library
are kept in `rover_gazebo/{worlds,models}` as assets but are unused by `fleet_sim.sh`.

## Fleet start (one command)

The whole robot starts from the Pi5: `~/ros2_ws/scripts/fleet.sh {sim|rover|stop|down|status}`.
In `sim` mode the Pi5 sshes here and runs `fleet_sim.sh`. Requires sshd here with the Pi5's
key in `~/.ssh/authorized_keys` (done 2026-07-07). Logs: `/workspace/ros2_ws/logs/`.

- **`/cmd_vel` is plain Twist**, run through `contract_bridge.py`'s firmware port: PWM
  deadband floor (`vx=0.03` → drives ≈0.168 m/s), 0.02 dead-stick, 0.30 m/s full scale,
  0.5 s watchdog, track 0.24. Keep the constants byte-identical to `rover_firmware.ino` on
  the Pi5. Nav2 must stream commands continuously and expect no smooth low-speed regime.
- **Camera**: `/camera/camera0/{color,infra1,depth,motion}`, 896×504, 15 Hz; depth is
  **16UC1 mm** (0=invalid), IMU `/camera/camera0/motion/sample` 200 Hz in
  `camera0_motion_optical_frame` (no orientation, cov[0]=-1). **Wall-clock stamps** →
  consumers use `use_sim_time:=false`; there is NO `/clock`.
- **The sim publishes no odometry** — the Jetson's visual SLAM is the sole pose source
  (`map→odom`, `odom→base_link`), matching the real robot (no wheel encoders). The robot only
  owns the captured `camera0_*` `/tf_static` tree.
- Known divergences (accepted): centered principal point vs real off-center; noise-free IMU;
  4-wheel skid-steer turns slightly easier than real. Details in `docs/INTERFACE.md`.
- `d555_contract/` = captured REAL camera_infos + frame tree; never hand-edit, recapture from
  hardware. `docs/REAL_ROBOT_SWAP.md` covers the sim↔real flip.

## Networking — OPEN QUESTION (reconcile before touching)

`fleet_sim.sh` runs the parity pipeline on **plain domain-0 multicast** (it `unset`s
`ROS_DISCOVERY_SERVER`/`FASTRTPS_DEFAULT_PROFILES_FILE`), verified working 2026-07-17. But
the Pi5 `~/ros2_ws/NETWORKING.md` says the fleet uses a **Fast DDS Discovery Server** on the
Pi5 (port 11811) because home routers drop multicast, and `fleet_env.sh` here still pins that.
These two stories conflict. Before changing either: confirm on real WiFi whether multicast
survives between laptop/Pi5/Jetson, or whether the parity pipeline needs the discovery server
too. `fleet_env.sh` is retained but NOT sourced by the new `fleet_sim.sh`.

- Gotcha (NETWORKING.md, 2026-07-06): `ros2 node list` via the discovery server returns empty
  even while pub/sub works — verify links by echoing a live topic instead.
- mDNS resolves `rakhi24-desktop.local` and `rakhi-jetson.local` from here (2026-07-07).

## The machines

| Machine | Role | Repo (local path) | mDNS / ssh |
|---|---|---|---|
| This laptop | this sim | `/workspace/ros2_ws/src/rover_sim` | hostname `rakhi24` |
| Pi 5 | LangGraph brain, micro-ROS agent | `~/ros2_ws` (pi5_ros2_ws) | `ssh rakhi24@rakhi24-desktop.local` (192.168.1.16) |
| Jetson Orin | RTAB-Map/cuVSLAM + nvblox + Nav2 (`isaac_ros`), STT/TTS/YOLO (`ai_stack`) | `~/robot` (speech_vision) | `ssh rakhi24@rakhi-jetson.local` (192.168.1.15) |
| Mac Mini | LLM server (llama.cpp) | — | `singireddys-mac-mini.local:8080` |
| ESP32 | real wheels via micro-ROS (UDP 8888 to Pi5) | — | — |

## Conventions

- `GZ_PARTITION=rover_sim` is exported by `fleet_sim.sh` — a second gz instance on the
  machine otherwise steals the robot spawn. Debug with `GZ_PARTITION=rover_sim gz topic -l`.
  See [[gz-partition-second-sim]].
- `contract_bridge.py` ↔ `rover_firmware.ino` is the fleet's ONLY intentional code
  duplication — the drive constants must stay in sync.
- Keep machine/interface details here in sync with the Pi5 repo's CLAUDE.md and the Jetson
  repo's CLAUDE.md — change all three together or none. **This pivot needs propagating there:
  the Jetson/Pi5 must consume `/camera/camera0/*` + `/cmd_vel`, not `/cam_1/*`/TwistStamped.**
