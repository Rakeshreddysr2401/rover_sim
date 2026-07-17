#!/usr/bin/env bash
# Start/stop/status for the sim as a FLEET MEMBER (called by the Pi5's
# scripts/fleet.sh over ssh, or run directly on this laptop).
#
#   ./fleet_sim.sh start    # idempotent; GUI if a display is up, else headless
#   ./fleet_sim.sh stop
#   ./fleet_sim.sh status
#
# Env overrides: WORLD=house|cafe|empty (default house).
#
# The sim is a stand-in for the REAL ROVER ONLY: 4-wheel mecanum base + a
# D555-style depth camera with built-in IMU + the world. No Nav2/SLAM/EKF here —
# mapping and navigation (cuVSLAM/RTABMap, nvblox, Nav2) run on the Jetson,
# reasoning on the Pi5. See docs/INTERFACE.md.
#
# Joins the Pi5 discovery server via fleet_env.sh; if the Pi5 is unreachable
# the sim still starts, standalone (plain local discovery).

set -eo pipefail
CMD="${1:-status}"
WORLD="${WORLD:-house}"

if [ -n "${MODE:-}" ]; then
    echo "fleet_sim: NOTE: MODE=$MODE ignored — SLAM/Nav2 moved to the Jetson (this sim is rover+camera+world only)"
fi

WS=/workspace/ros2_ws
LOG_DIR="$WS/logs"
LOG="$LOG_DIR/fleet_sim.log"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

stop_sim() {
    # Kill ONLY this repo's sim. Patterns are anchored to rover_gazebo paths /
    # this launch's names — a plain "[g]z sim" pattern once killed an unrelated
    # Gazebo instance (~/langrobo) that happened to be running on this laptop.
    # Bracket trick so pkill doesn't match this script's own command line.
    pkill -9 -f "[r]over.gazebo.launch" 2>/dev/null || true
    pkill -9 -f "gz sim.*[r]over_gazebo/share" 2>/dev/null || true
    pkill -9 -f "[p]arameter_bridge --ros-args --params-file" 2>/dev/null || true
    pkill -9 -f "[i]mage_bridge.*cam_1" 2>/dev/null || true
    pkill -9 -f "[r]obot_state_publisher --ros-args" 2>/dev/null || true
    pkill -9 -f "[r]viz2.*rover" 2>/dev/null || true
    sleep 1
}

sim_running() {
    pgrep -f "[r]over.gazebo.launch" >/dev/null
}

case "$CMD" in
start)
    if sim_running; then
        echo "fleet_sim: already running (WORLD of the running instance unchanged)"
        exit 0
    fi
    stop_sim
    mkdir -p "$LOG_DIR"

    set +u
    source /opt/ros/jazzy/setup.bash
    source "$WS/install/setup.bash"
    # Join the fleet meeting point (no-op locally if Pi5 is down: env just
    # points at an unreachable server, so fall back to standalone instead).
    if getent ahostsv4 rakhi24-desktop.local >/dev/null 2>&1; then
        source "$SELF_DIR/fleet_env.sh"
    else
        echo "fleet_sim: Pi5 not resolvable — starting STANDALONE (local discovery)"
    fi
    set -u

    # GUI when this laptop has a live display session; headless otherwise
    # (e.g. started over ssh with nobody logged in).
    HEADLESS=True
    if [ -e /tmp/.X11-unix/X0 ]; then
        export DISPLAY="${DISPLAY:-:0}"
        XAUTH=$(ls /run/user/$(id -u)/.mutter-Xwaylandauth.* 2>/dev/null | head -1)
        [ -n "$XAUTH" ] && export XAUTHORITY="$XAUTH"
        if xset q >/dev/null 2>&1; then HEADLESS=False; fi
    fi

    if [ "$WORLD" = "cafe" ]; then SPAWN_Z=0.20; else SPAWN_Z=0.05; fi

    # Isolate this sim's gz-transport from any other Gazebo instance on the
    # machine (without this, a second gz server steals the robot spawn: the
    # world-list/create requests cross-talk). Debug shells must match:
    #   GZ_PARTITION=rover_sim gz topic -l
    export GZ_PARTITION=rover_sim

    echo "fleet_sim: starting WORLD=$WORLD headless=$HEADLESS (log: $LOG)"
    # enable_odom_tf: the robot owns odom->base_footprint (wheel odometry);
    # the Jetson's SLAM provides map->odom on top (REP-105 split).
    nohup ros2 launch rover_gazebo rover.gazebo.launch.py \
        enable_odom_tf:=true headless:=$HEADLESS \
        use_rviz:=$([ "$HEADLESS" = "False" ] && echo true || echo false) \
        jsp_gui:=false load_controllers:=true use_sim_time:=true \
        world_file:=${WORLD}.world x:=0.0 y:=0.0 z:=$SPAWN_Z > "$LOG" 2>&1 &
    disown
    echo "fleet_sim: launched (drive ready when status reports 2/2 controllers; check with: $0 status)"
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
    set +u
    source /opt/ros/jazzy/setup.bash >/dev/null 2>&1
    source "$WS/install/setup.bash" >/dev/null 2>&1
    # Mirror the discovery env the sim was started with, or this shell can't
    # see its nodes. SUPER_CLIENT lets CLI introspection work via the server.
    if getent ahostsv4 rakhi24-desktop.local >/dev/null 2>&1; then
        source "$SELF_DIR/fleet_env.sh" >/dev/null
        export ROS_SUPER_CLIENT=TRUE
    fi
    set -u
    # Probe via services (reliable through the discovery server; `ros2
    # lifecycle get` / node lists are not — see NETWORKING.md red herring).
    CTRL=$(timeout 10 ros2 control list_controllers 2>/dev/null | grep -c "active" || true)
    echo "fleet_sim: running — active controllers: ${CTRL:-0}/2 (2 = drive ready)"
    ;;
*)
    echo "usage: $0 {start|stop|status}   (env: WORLD=house|cafe|empty)"
    exit 2
    ;;
esac
