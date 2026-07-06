# rover_sim — working notes

Simulation stand-in for the real mecanum rover. ROS 2 Jazzy + Gazebo (gz-sim 8), Ubuntu 24.04.
Workspace: `/workspace/ros2_ws` (HDD partition; keep large artifacts — bags, maps, models —
under `/workspace`, not the SSD home dir).

## Build & run

```bash
cd /workspace/ros2_ws && colcon build --symlink-install && source install/setup.bash
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_gazebo.sh        # sim only (WORLD=cafe|house)
./src/rover_sim/rover_bringup/scripts/rosmaster_x3_navigation.sh    # sim + nav2 (add "slam" arg for SLAM)
```

- cmd_vel is **TwistStamped** on `/mecanum_drive_controller/cmd_vel`; plain `/cmd_vel` only
  exists when Nav2 is up (relay restamps it).
- `house.world` ≈ 0.1 RTF on this iGPU laptop; `empty.world` ≈ 1.0 RTF.
- Full topic/action/frame contract: `docs/INTERFACE.md`. Real-robot swap: `docs/REAL_ROBOT_SWAP.md`.

## Machine IPs (keep in sync with speech_vision repo's CLAUDE.md if either changes)

- Pi 5 (brain / langrobo_core, ros2_ws): 192.168.2.10, `ssh rakhi24@192.168.2.10`,
  wifi 192.168.1.16
- Jetson Orin (speech_vision): 192.168.2.20, `ssh rakhi24@192.168.2.20`, wifi 192.168.1.15
- This laptop (sim): wifi 192.168.1.12 (dhcp — verify with `ip -4 addr show wlo1`)
- `ROS_DOMAIN_ID=0` on all machines.

## Conventions

- Packages are `rover_*`; the robot variant is `rosmaster_x3` (xacro in
  `rover_description/urdf/robots/`, controller config in `rover_description/config/<variant>/`).
- No hardcoded absolute paths in launch files — resolve via
  `get_package_share_directory`/`FindPackageShare` (upstream had `~/ros2_ws` hardcoded; fixed).
- Sim-only nodes (Gazebo, bridge, spawner) live only in `rover_gazebo`.
- Adapted from automaticaddison/yahboom_rosmaster (BSD-3); per-package LICENSE files retained.
