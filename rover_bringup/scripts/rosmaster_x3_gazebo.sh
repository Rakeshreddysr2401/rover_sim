#!/bin/bash
# Single script to launch the Yahboom ROSMASTERX3 with Gazebo and ROS 2 Controllers

cleanup() {
    echo "Cleaning up..."
    sleep 5.0
    # Only this repo's processes — do NOT blanket-kill "gz|ros2" (there may be
    # other Gazebo/ROS work running on this laptop, e.g. ~/langrobo).
    pkill -9 -f "rover.gazebo.launch" 2>/dev/null
    pkill -9 -f "gz sim.*rover_gazebo/share" 2>/dev/null
    pkill -9 -f "parameter_bridge --ros-args --params-file" 2>/dev/null
    pkill -9 -f "image_bridge.*cam_1" 2>/dev/null
    pkill -9 -f "robot_state_publisher --ros-args" 2>/dev/null
    pkill -9 -f "rviz2.*rover" 2>/dev/null
}

# Set up cleanup trap
trap 'cleanup' SIGINT SIGTERM

# To change Gazebo camera pose: gz service -s /gui/move_to/pose --reqtype gz.msgs.GUICamera --reptype gz.msgs.Boolean --timeout 2000 --req "pose: {position: {x: 0.0, y: -2.0, z: 2.0} orientation: {x: -0.2706, y: 0.2706, z: 0.6533, w: 0.6533}}"
# World selection: WORLD=house (default) or WORLD=cafe, e.g. WORLD=cafe ./rosmaster_x3_gazebo.sh
WORLD="${WORLD:-house}"
if [ "$WORLD" = "cafe" ]; then SPAWN_Z=0.20; else SPAWN_Z=0.05; fi

# Isolate this sim's gz-transport from any other Gazebo instance on the machine
# (a second gz server otherwise steals the robot spawn). Debug shells must match:
#   GZ_PARTITION=rover_sim gz topic -l
export GZ_PARTITION=rover_sim

echo "Launching Gazebo simulation..."
ros2 launch rover_gazebo rover.gazebo.launch.py \
    enable_odom_tf:=true \
    headless:=False \
    load_controllers:=true \
    world_file:=${WORLD}.world \
    use_rviz:=true \
    use_robot_state_pub:=true \
    use_sim_time:=true \
    x:=0.0 \
    y:=0.0 \
    z:=${SPAWN_Z} \
    roll:=0.0 \
    pitch:=0.0 \
    yaw:=0.0 &

echo "Waiting 25 seconds for simulation to initialize..."
sleep 25
echo "Adjusting camera position..."
gz service -s /gui/move_to/pose --reqtype gz.msgs.GUICamera --reptype gz.msgs.Boolean --timeout 2000 --req "pose: {position: {x: 0.0, y: -2.0, z: 2.0} orientation: {x: -0.2706, y: 0.2706, z: 0.6533, w: 0.6533}}"

# Keep the script running until Ctrl+C
wait
