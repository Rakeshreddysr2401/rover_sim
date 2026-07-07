# Source (don't execute) before launching the sim when the real fleet is up:
#   source src/rover_sim/rover_bringup/scripts/fleet_env.sh
#
# Registers every sim node with the Pi5 "meeting point" (Fast DDS Discovery
# Server, langrobo-discovery.service) so the LangGraph brain — a discovery-
# server client — sees the sim graph. Same convention as the Jetson
# containers (see Pi5 ~/ros2_ws/NETWORKING.md).
#
# NOTE: in this mode the sim's DDS discovery depends on the Pi5 being up.
# For laptop-only sim work, skip this file (plain multicast works locally).
#
# Resolve the Pi by name but pin IPv4 — mDNS prefers IPv6 and the discovery
# server is UDPv4-only, which fails silently (bitten 2026-07-06).

export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp

_pi5_ip=$(getent ahostsv4 rakhi24-desktop.local 2>/dev/null | awk 'NR==1{print $1}')
export ROS_DISCOVERY_SERVER="${_pi5_ip:-192.168.1.16}:11811"
unset _pi5_ip
echo "ROS_DISCOVERY_SERVER=$ROS_DISCOVERY_SERVER"
