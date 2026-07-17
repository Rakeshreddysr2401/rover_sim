#!/usr/bin/env bash
# Start/stop/status for the sim as a FLEET MEMBER (called by the Pi5's
# scripts/fleet.sh over ssh, or run directly on this laptop).
#
#   ./fleet_sim.sh start    # idempotent, headless; the whole 4-stage pipeline
#   ./fleet_sim.sh status   # prints the /rover_sim/status counters
#   ./fleet_sim.sh stop
#   ./fleet_sim.sh gui      # attach a Gazebo GUI to the running headless server
#
# The sim IMPERSONATES THE REAL ROVER (imported from ~/langrobo/rover_sim,
# 2026-07-17): a 4-wheel skid-steer base + RealSense D555 rig publishing the
# exact hardware contract — /camera/camera0/* with wall-clock stamps and the
# captured real intrinsics/frame tree, /cmd_vel consumed through a
# byte-accurate port of the ESP32 firmware (PWM deadband, 500ms watchdog).
# The Jetson/Pi5 stack runs unchanged and cannot tell it is in simulation.
# Contract: docs/INTERFACE.md.
#
#   stage 1  gz sim (headless server, RTF 1.0)   world + rover model
#   stage 2  ros_gz parameter_bridge             gz <-> ROS, internal /rover_sim/*
#   stage 3  rover_contract restamper (C++)      contract names, wall stamps, 16UC1 depth
#   stage 4  rover_contract contract_bridge.py   imu remap, firmware emu, tf, status
#
# NOTE: wall-clock stamps require RTF ~= 1.0, so the fleet world is the small
# langrobo_home room. house/cafe (0.1 RTF on this iGPU) are kept in
# rover_gazebo/worlds as assets only — they'd break stamp parity here.

set -eo pipefail
CMD="${1:-status}"
WORLD="${WORLD:-langrobo_home}"

WS=/workspace/ros2_ws
LOG_DIR="$WS/logs"

# Isolate this sim's gz-transport from any other Gazebo instance on the
# machine (without this, a second gz server steals the robot spawn: the
# world-list/create requests cross-talk). Debug shells must match:
#   GZ_PARTITION=rover_sim gz topic -l
export GZ_PARTITION=rover_sim

setup_env() {
    set +u
    source /opt/ros/jazzy/setup.bash
    source "$WS/install/setup.bash"
    set -u
    # Parity stack runs on plain domain-0 discovery (verified working
    # 2026-07-17); the Pi5 discovery-server scheme is NOT used on this path —
    # reconcile with NETWORKING.md before changing either.
    unset ROS_DISCOVERY_SERVER FASTRTPS_DEFAULT_PROFILES_FILE
    export ROS_DOMAIN_ID=0
    GZ_SHARE=$(ros2 pkg prefix rover_gazebo)/share/rover_gazebo
    CONTRACT_SHARE=$(ros2 pkg prefix rover_contract)/share/rover_contract
    export GZ_SIM_RESOURCE_PATH="$GZ_SHARE/models"
}

stop_sim() {
    # Kill ONLY this repo's sim (patterns anchored to our paths/topic names —
    # a plain "gz sim" pattern once killed an unrelated Gazebo instance).
    pkill -f "[c]ontract_bridge.py" 2>/dev/null || true
    pkill -f "[r]over_contract/restamper" 2>/dev/null || true
    pkill -f "[p]arameter_bridge.*rover_sim/" 2>/dev/null || true
    pkill -f "gz sim.*[r]over_gazebo/share" 2>/dev/null || true
    pkill -9 -f "ruby.*gz sim.*[r]over_gazebo/share" 2>/dev/null || true
    sleep 1
}

sim_running() {
    pgrep -f "gz sim.*[r]over_gazebo/share" >/dev/null
}

case "$CMD" in
start)
    if sim_running; then
        echo "fleet_sim: already running"
        exit 0
    fi
    stop_sim
    mkdir -p "$LOG_DIR"
    setup_env

    WORLD_FILE="$GZ_SHARE/worlds/${WORLD}.sdf"
    if [ ! -f "$WORLD_FILE" ]; then
        echo "fleet_sim: [FAIL] no such world: $WORLD_FILE" >&2
        echo "  (only langrobo_home embeds the rover; house/cafe are assets only)" >&2
        exit 1
    fi

    echo "fleet_sim: [1/4] gz sim (headless, ${WORLD}.sdf)"
    # gz stamps start at sim-time 0; the restamper rewrites them to the wall
    # clock. Do NOT use --initial-sim-time with an epoch value — it silently
    # breaks all sensor/stats scheduling (found live 2026-07-17).
    nohup setsid gz sim -s -r --headless-rendering \
        "$WORLD_FILE" > "$LOG_DIR/gz_sim.log" 2>&1 < /dev/null &
    for i in $(seq 1 30); do
        gz topic -l 2>/dev/null | grep -q "/rover_sim/infra1/image" && break
        [ "$i" = 30 ] && { echo "fleet_sim: [FAIL] gz sensors never came up — $LOG_DIR/gz_sim.log" >&2; exit 1; }
        sleep 2
    done
    echo "fleet_sim:   [ok] world + sensors up"

    echo "fleet_sim: [2/4] ros_gz parameter_bridge (internal /rover_sim names)"
    nohup ros2 run ros_gz_bridge parameter_bridge \
        /rover_sim/infra1/image@sensor_msgs/msg/Image[gz.msgs.Image \
        /rover_sim/infra1/camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo \
        /rover_sim/depth/image@sensor_msgs/msg/Image[gz.msgs.Image \
        /rover_sim/depth/camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo \
        /rover_sim/color/image@sensor_msgs/msg/Image[gz.msgs.Image \
        /rover_sim/color/camera_info@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo \
        /rover_sim/imu@sensor_msgs/msg/Imu[gz.msgs.IMU \
        /rover_sim/drive_cmd@geometry_msgs/msg/Twist]gz.msgs.Twist \
        > "$LOG_DIR/gz_bridge.log" 2>&1 &
    sleep 3
    echo "fleet_sim:   [ok] bridge up"

    echo "fleet_sim: [3/4] restamper (C++: contract names, wall stamps, depth 16UC1)"
    nohup ros2 run rover_contract restamper > "$LOG_DIR/restamper.log" 2>&1 &
    echo "fleet_sim:   [ok] restamper up"

    echo "fleet_sim: [4/4] contract bridge (imu + drive emulation + tf + marker)"
    nohup ros2 run rover_contract contract_bridge.py \
        --contract "$CONTRACT_SHARE/d555_contract" --role motion \
        > "$LOG_DIR/contract_bridge.log" 2>&1 &
    sleep 3
    timeout 10 ros2 topic echo --once /rover_sim/status >/dev/null 2>&1 \
        && echo "fleet_sim:   [ok] contract topics live" \
        || { echo "fleet_sim: [FAIL] contract bridge — $LOG_DIR/contract_bridge.log" >&2; exit 1; }

    echo "fleet_sim: UP — /camera/camera0/* publishing on domain 0 (logs: $LOG_DIR)"
    ;;
stop)
    stop_sim
    echo "fleet_sim: stopped"
    ;;
status)
    if ! sim_running; then
        echo "fleet_sim: NOT running"
        exit 1
    fi
    setup_env >/dev/null 2>&1
    S=$(timeout 10 ros2 topic echo --once --field data /rover_sim/status 2>/dev/null | head -1)
    if [ -n "$S" ]; then
        echo "fleet_sim: running — $S"
    else
        echo "fleet_sim: gz up but contract bridge NOT publishing status" >&2
        exit 1
    fi
    ;;
gui)
    if ! sim_running; then
        echo "fleet_sim: NOT running (start first)"
        exit 1
    fi
    exec gz sim -g
    ;;
*)
    echo "usage: $0 {start|stop|status|gui}   (env: WORLD=langrobo_home)"
    exit 2
    ;;
esac
