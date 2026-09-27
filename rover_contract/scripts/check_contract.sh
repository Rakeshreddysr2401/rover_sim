#!/usr/bin/env bash
# check_contract.sh — D555/ESP32 robot parity gate.
#
# Asserts the robot contract (docs/INTERFACE.md) that the sim and the real
# rover must BOTH satisfy identically: /camera/camera0/* topics + rates +
# formats + frames, the captured /tf_static tree, and a live /cmd_vel consumer.
# Runs the same against sim (fleet_sim.sh on the laptop) and real hardware —
# it must be as green in one as the other. Exits non-zero on any hard failure.
#
#   ./check_contract.sh                 # full gate
#   CAM=/camera/camera0 ./check_contract.sh
#   ./check_contract.sh --slam          # also require map->odom (SLAM up)
#
# Deliberately passive: it never drives the robot (there is no odom to observe
# the effect anyway) — it only checks a subscriber exists on /cmd_vel.

set -o pipefail

CAM="${CAM:-/camera/camera0}"
REQUIRE_SLAM=0
[ "${1:-}" = "--slam" ] && REQUIRE_SLAM=1

# ---- ROS env (edit if your overlay differs) -------------------------------
# ROS setup.bash references unbound vars — never source it under `set -u`.
source /opt/ros/jazzy/setup.bash 2>/dev/null || true
# Overlay: Jetson (~/robot) or the rover_sim workspace, whichever exists.
for o in "$HOME/robot/install/setup.bash" /workspace/ros2_ws/install/setup.bash; do
  [ -f "$o" ] && { source "$o" 2>/dev/null || true; break; }
done
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"

# ---- pretty + tallies -----------------------------------------------------
RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; DIM=$'\e[2m'; RST=$'\e[0m'
PASS=0; FAIL=0; WARN=0
ok()   { echo "  ${GRN}PASS${RST} $1"; PASS=$((PASS+1)); }
bad()  { echo "  ${RED}FAIL${RST} $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ${YLW}WARN${RST} $1"; WARN=$((WARN+1)); }

# Sample a topic's publish rate (Hz) over a short window. Echoes a number or "".
rate_of() {  # topic, window_s
  timeout "${2:-6}" ros2 topic hz "$1" 2>/dev/null \
    | awk '/average rate/ {r=$3} END {if (r) print r}'
}
# First value of one message field, or "" on timeout. Filters the
# "A message was lost!!!" / "total count" chatter ros2 topic echo prints to
# STDOUT under lossy sensor QoS, which would otherwise masquerade as the value.
field_of() {  # topic, field, timeout_s
  timeout "${3:-8}" ros2 topic echo --once --field "$2" "$1" 2>/dev/null \
    | grep -vE 'message was lost|total count|^---' | head -1
}
have_topic() { ros2 topic list 2>/dev/null | grep -qx "$1"; }

# check_stream TOPIC MIN_HZ MAX_HZ
check_stream() {
  local t="$1" lo="$2" hi="$3"
  if ! have_topic "$t"; then bad "$t missing"; return; fi
  local r; r=$(rate_of "$t" 6)
  if [ -z "$r" ]; then bad "$t present but no messages"; return; fi
  if awk "BEGIN{exit !($r>=$lo && $r<=$hi)}"; then
    ok "$t @ ${r} Hz  ${DIM}(want ${lo}-${hi})${RST}"
  else
    bad "$t @ ${r} Hz  ${DIM}(want ${lo}-${hi})${RST}"
  fi
}

echo "== D555/ESP32 contract gate  (cam=$CAM, domain=$ROS_DOMAIN_ID) =="

# ---- 0. mode marker: sim vs real -----------------------------------------
if have_topic /rover_sim/status; then
  MODE="SIM"; echo "${DIM}mode: SIM  (/rover_sim/status present)${RST}"
else
  MODE="REAL"; echo "${DIM}mode: REAL (no /rover_sim/status marker)${RST}"
fi

# ---- 1. image + imu streams (rate) ---------------------------------------
# Nominal contract: images 15 Hz, IMU 200 Hz. Bands are wide on purpose: they
# only catch a stalled/dead/way-off stream, not jitter. The sim renders hot
# (~16-26 Hz images) on some GPUs; the real D555's unite_imu runs 200 or 400.
echo "-- streams --"
check_stream "$CAM/color/image_raw"        10 30
check_stream "$CAM/infra1/image_rect_raw"  10 30
check_stream "$CAM/depth/image_rect_raw"   10 30
check_stream "$CAM/motion/sample"         120 420

# ---- 2. depth format + frame ---------------------------------------------
echo "-- depth format --"
enc=$(field_of "$CAM/depth/image_rect_raw" encoding 8)
[ "$enc" = "16UC1" ] && ok "depth encoding 16UC1" \
                      || bad "depth encoding '${enc:-<none>}' (want 16UC1, mm)"
dfr=$(field_of "$CAM/depth/image_rect_raw" header.frame_id 8)
case "$dfr" in *camera0_depth_optical_frame) ok "depth frame $dfr";;
  *) bad "depth frame '${dfr:-<none>}' (want camera0_depth_optical_frame)";; esac

# ---- 3. imu semantics -----------------------------------------------------
echo "-- imu --"
ifr=$(field_of "$CAM/motion/sample" header.frame_id 8)
case "$ifr" in *camera0_motion_optical_frame) ok "imu frame $ifr";;
  *) bad "imu frame '${ifr:-<none>}' (want camera0_motion_optical_frame)";; esac
cov=$(field_of "$CAM/motion/sample" orientation_covariance 8)
case "$cov" in -1*|"[-1"*) ok "imu orientation_covariance[0]=-1 (no orientation, like D555)";;
  *) bad "imu orientation_covariance[0] not -1 (got '${cov:-<none>}')";; esac

# ---- 4. camera_info paired + sane ----------------------------------------
echo "-- camera_info --"
for s in color infra1 depth; do
  w=$(field_of "$CAM/$s/camera_info" width 6)
  k=$(field_of "$CAM/$s/camera_info" k 6)   # k[0]=fx
  fx=$(echo "$k" | tr -d '[],' | awk '{print $1}')
  if [ -n "$w" ] && awk "BEGIN{exit !($w>0)}" 2>/dev/null && \
     [ -n "$fx" ] && awk "BEGIN{exit !($fx>0)}" 2>/dev/null; then
    ok "$s/camera_info  ${DIM}(w=$w fx=$fx)${RST}"
  else
    bad "$s/camera_info missing/degenerate (w='${w:-}' fx='${fx:-}')"
  fi
done

# ---- 5. static frame tree -------------------------------------------------
echo "-- tf --"
tf=$(timeout 8 ros2 topic echo --once /tf_static 2>/dev/null)
if echo "$tf" | grep -q "camera0_link"; then
  for f in camera0_color_optical_frame camera0_depth_optical_frame camera0_infra1_optical_frame; do
    echo "$tf" | grep -q "$f" && ok "/tf_static has $f" || bad "/tf_static missing $f"
  done
else
  bad "/tf_static has no camera0_* frames"
fi

# ---- 6. drive path: a subscriber on /cmd_vel ------------------------------
echo "-- drive --"
subs=$(ros2 topic info /cmd_vel 2>/dev/null | awk '/Subscription count/ {print $3}')
if [ "${subs:-0}" -ge 1 ] 2>/dev/null; then
  ok "/cmd_vel has $subs subscriber(s) (firmware/DiffDrive consumer alive)"
else
  bad "/cmd_vel has no subscriber — nothing will drive the wheels"
fi

# ---- 7. optional: SLAM up (map->odom) ------------------------------------
if [ "$REQUIRE_SLAM" = 1 ]; then
  echo "-- slam (--slam) --"
  if timeout 6 ros2 run tf2_ros tf2_echo map odom >/dev/null 2>&1; then
    ok "map->odom transform available"
  else
    bad "map->odom not available (visual SLAM not up / not localized)"
  fi
else
  warn "SLAM (map->odom) not checked — pass --slam to require it"
fi

# ---- verdict --------------------------------------------------------------
echo "== $MODE: ${GRN}${PASS} pass${RST}, ${YLW}${WARN} warn${RST}, ${RED}${FAIL} fail${RST} =="
[ "$FAIL" -eq 0 ] || exit 1
