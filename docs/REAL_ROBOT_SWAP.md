# Swapping the simulation for the real rover

Because the sim **impersonates** the real robot's contract exactly (captured intrinsics,
wall-clock stamps, firmware-emulated `/cmd_vel` — see [INTERFACE.md](INTERFACE.md)), the
Jetson and Pi 5 code does not change at all. Switching between sim and real is a single
config flip on the Jetson.

## The switch

On the Jetson (`~/robot`):

```bash
echo real > config/hardware   # was: sim
robot restart
scripts/check_contract.sh     # must be as green as sim mode
```

`sim` mode expects the laptop pipeline (`fleet_sim.sh start`) up; `real` mode brings up the
physical drivers below instead. Same topics, same frames, same firmware behavior either way.

## What each side provides

| Contract element | Sim source | Real source |
|---|---|---|
| `/camera/camera0/*` (color, infra1, depth, motion) | gz D555 rig → `rover_contract` restamper/bridge | `realsense-ros`, `camera_name:=camera0`, aligned depth, `unite_imu_method:=2` |
| depth format | restamper casts 32FC1 m → 16UC1 mm | driver already 16UC1 mm |
| wall-clock stamps | restamper stamps `now()` | driver stamps real time |
| captured `/tf_static` | `contract_bridge.py` replays `d555_contract/*.yaml` | the real camera + `run_robot_tf.sh` |
| `/cmd_vel` behavior | `contract_bridge.py` firmware port → gz DiffDrive | `rover_firmware.ino` on the ESP32 via micro-ROS (UDP 8888 → Pi5 agent) |
| `map→odom` / pose | Jetson visual SLAM (unchanged) | Jetson visual SLAM (unchanged) |

## The one thing to keep in sync

`rover_contract/scripts/contract_bridge.py` is a **port of `rover_firmware.ino`**
(`PWM_MIN`, `MAX_LINEAR_VEL`, `MAX_ANGULAR_VEL`, `DEAD_STICK`, `CMD_TIMEOUT_S`, `TRACK`). If
the real firmware's constants change, change them in the port too, or sim and real drive
differently. This is the only intentional code duplication in the fleet.

## Recapturing the D555 contract

`rover_contract/d555_contract/` holds camera_infos + the static frame tree **captured from
the real camera** — never hand-edit them. If the real camera, its mount, or its resolution
changes, recapture (record `/camera/camera0/*/camera_info` and `/tf_static` from the real
driver, save the yamls) and rebuild. The sim's gz intrinsics (hfov in `models/rover/model.sdf`)
should then be re-derived from the new `fx`.

## Divergences that remain on the real robot

None that the stack sees — but be aware the sim's known gaps (centered principal point,
noise-free IMU, easier skid-steer turns; see INTERFACE.md) mean anything tuned *against the
sim* — VIO noise models, low-speed controller gains — must be re-checked on real hardware.
