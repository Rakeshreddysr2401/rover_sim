# rover_sim — working notes

Simulation stand-in for the real mecanum rover ("Rakhi" home robot fleet). ROS 2 Jazzy +
Gazebo (gz-sim 8), Ubuntu 24.04. GitHub: https://github.com/Rakeshreddysr2401/rover_sim.
Workspace: `/workspace/ros2_ws` (HDD partition; keep large artifacts — bags, maps, models —
under `/workspace`, not the SSD home dir).

## Build & run

```bash
cd /workspace/ros2_ws && colcon build --symlink-install && source install/setup.bash
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_gazebo.sh        # sim only (WORLD=cafe|house)
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_navigation.sh    # sim + nav2 (add "slam" arg for SLAM)
```

## Fleet start (one command)

The whole robot starts from the Pi5: `~/ros2_ws/scripts/fleet.sh {sim|rover|stop|down|status}`
(`stop` parks the body but keeps the brain/Telegram up; `down` is a full shutdown incl. the
Pi5 services).
In `sim` mode the Pi5 sshes here and runs this repo's fleet member script, which also works
directly on this laptop:

```bash
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh start    # GUI if logged in, headless over ssh
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh status   # "2/2 active controllers" = drive ready
./src/rover_sim/rover_bringup/scripts/fleet_sim.sh stop
# env: WORLD=house|cafe  MODE=slam|map  (map mode auto-localizes at the spawn pose)
```

`fleet_sim.sh start` joins the Pi5 discovery server automatically when the Pi5 resolves,
else starts standalone. Requires sshd here (installed + enabled 2026-07-07) with the Pi5's
key in `~/.ssh/authorized_keys` (done). Logs: `/workspace/ros2_ws/logs/fleet_sim.log`.

- cmd_vel is **TwistStamped** on `/mecanum_drive_controller/cmd_vel`; plain `/cmd_vel` only
  exists when Nav2 is up (relay restamps it).
- `house.world` ≈ 0.1 RTF on this iGPU laptop; `empty.world` ≈ 1.0 RTF.
- Camera mirrors RealSense D555 naming (`/cam_1/color/*`, `/cam_1/depth/image_rect_raw`,
  `/cam_1/depth/camera_info`, `/cam_1/depth/color/points`) at 15 Hz, 8 m depth range — so
  the Jetson's nvblox/Isaac ROS pipelines consume the sim without remapping.
- Full topic/action/frame contract: `docs/INTERFACE.md`. Real-robot swap: `docs/REAL_ROBOT_SWAP.md`.

## Fleet networking (Fast DDS Discovery Server — see Pi5 `~/ros2_ws/NETWORKING.md`)

The fleet does NOT use default multicast discovery (home routers drop it) and the old
hand-edited `fastdds_unicast.xml` peer lists are **retired**. A Fast DDS Discovery Server
("meeting point") runs on the Pi5 as `langrobo-discovery.service`, port 11811, always-on.
Machines are addressed by mDNS name, never by hardcoded wifi IP.

To connect this sim to the fleet, source **before launching** (pins IPv4 — mDNS prefers
IPv6 and the discovery server is UDPv4-only, which fails silently):

```bash
source src/rover_sim/rover_bringup/scripts/fleet_env.sh
```

For standalone sim work (Pi5 off / not needed), just don't set it — everything is local.

- Gotcha (from NETWORKING.md, verified 2026-07-06): `ros2 node list` via the discovery
  server is a red herring on this Jazzy build — it returns empty even while pub/sub works.
  Verify links by echoing a continuously-published topic instead.
- mDNS from this laptop resolves `rakhi24-desktop.local` and `rakhi-jetson.local` (verified
  2026-07-07).

## The machines

| Machine | Role | Repo (local path) | mDNS / ssh |
|---|---|---|---|
| This laptop | Gazebo sim (this repo) | `/workspace/ros2_ws/src/rover_sim` | hostname `rakhi24` |
| Pi 5 | LangGraph brain, discovery server, micro-ROS agent | `~/ros2_ws` (pi5_ros2_ws: langrobo_core/langrobo_ros) | `ssh rakhi24@rakhi24-desktop.local` (wifi 192.168.1.16) |
| Jetson Orin | STT/TTS/music/camera/YOLO in `ai_stack`; Isaac ROS in `isaac_ros` container | `~/robot` (speech_vision) | `ssh rakhi24@rakhi-jetson.local` (wifi 192.168.1.15) |
| Mac Mini | LLM server (llama.cpp) | — | `singireddys-mac-mini.local:8080` |
| ESP32 | real wheels via micro-ROS (UDP 8888 to Pi5) | — | — |

The Pi5↔Jetson ethernet (192.168.2.x) link was reported physically dead 2026-07-05; the
discovery-server scheme works over whatever network is up, so nothing here depends on it.

## Conventions

- Packages are `rover_*`; the robot variant is `rosmaster_x3` (xacro in
  `rover_description/urdf/robots/`, controller config in `rover_description/config/<variant>/`).
- No hardcoded absolute paths in launch files — resolve via
  `get_package_share_directory`/`FindPackageShare` (upstream had `~/ros2_ws` hardcoded; fixed).
- Sim-only nodes (Gazebo, bridge, spawner) live only in `rover_gazebo`.
- Adapted from automaticaddison/yahboom_rosmaster (BSD-3); per-package LICENSE files retained.
- Keep the machine/interface details in this file in sync with the Pi5 repo's CLAUDE.md and
  the Jetson repo's CLAUDE.md — change all three together or none.
