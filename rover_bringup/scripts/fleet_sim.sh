#!/usr/bin/env bash
# Start/stop/status for the sim as a FLEET MEMBER (called by the Pi5's
# scripts/fleet.sh over ssh, or run directly on this laptop).
#
#   ./fleet_sim.sh start    # idempotent; GUI if a display is up, else headless
#   ./fleet_sim.sh stop
#   ./fleet_sim.sh status
#
# Env overrides: WORLD=house|cafe (default house), MODE=slam|map (default slam).
# MODE=slam needs no initial pose and coordinates are reproducible because the
# robot always spawns at the same pose. MODE=map uses AMCL with the pre-made
# <WORLD>_world_map (initial pose auto-set to the spawn pose in nav params).
#
# Joins the Pi5 discovery server via fleet_env.sh; if the Pi5 is unreachable
# the sim still starts, standalone (plain local discovery).

set -eo pipefail
CMD="${1:-status}"
WORLD="${WORLD:-house}"
MODE="${MODE:-slam}"

WS=/workspace/ros2_ws
LOG_DIR="$WS/logs"
LOG="$LOG_DIR/fleet_sim.log"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

stop_sim() {
    # Bracket trick so pkill doesn't match this script's own command line.
    pkill -9 -f "[r]osmaster_x3_navigation.launch" 2>/dev/null || true
    pkill -9 -f "[r]over.gazebo.launch" 2>/dev/null || true
    pkill -9 -f "[g]z sim" 2>/dev/null || true
    for p in "[p]arameter_bridge" "[i]mage_bridge" "[r]obot_state_publisher" \
             "[e]kf_node" "[c]omponent_container" "[l]ifecycle_manager" \
             "[s]lam_toolbox" "[a]ssisted_teleop" "[c]md_vel_relay" \
             "[n]av_to_pose" "[r]viz2"; do
        pkill -9 -f "$p" 2>/dev/null || true
    done
    sleep 1
}

sim_running() {
    pgrep -f "[r]osmaster_x3_navigation.launch" >/dev/null
}

case "$CMD" in
start)
    if sim_running; then
        echo "fleet_sim: already running (WORLD/MODE of the running instance unchanged)"
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

    if [ "$MODE" = "slam" ]; then SLAM_ARG=True; else SLAM_ARG=False; fi
    if [ "$WORLD" = "cafe" ]; then SPAWN_Z=0.20; else SPAWN_Z=0.05; fi
    MAP=$(ros2 pkg prefix rover_navigation)/share/rover_navigation/maps/${WORLD}_world_map.yaml

    echo "fleet_sim: starting WORLD=$WORLD MODE=$MODE headless=$HEADLESS (log: $LOG)"
    nohup ros2 launch rover_bringup rosmaster_x3_navigation.launch.py \
        enable_odom_tf:=false headless:=$HEADLESS use_rviz:=$([ "$HEADLESS" = "False" ] && echo true || echo false) \
        use_sim_time:=true world_file:=${WORLD}.world x:=0.0 y:=0.0 z:=$SPAWN_Z \
        slam:=$SLAM_ARG map:=$MAP > "$LOG" 2>&1 &
    disown
    echo "fleet_sim: launched (nav2 takes ~1 min in $WORLD.world; check with: $0 status)"
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
    echo "usage: $0 {start|stop|status}   (env: WORLD=house|cafe MODE=slam|map)"
    exit 2
    ;;
esac
