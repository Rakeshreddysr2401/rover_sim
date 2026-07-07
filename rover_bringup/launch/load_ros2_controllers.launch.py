#!/usr/bin/env python3
"""
Launch ROS 2 controllers for the mecanum wheel robot.

This script creates a launch description that starts the necessary controllers
for operating the mecanum wheel robot in a specific sequence.

Launched Controllers:
    1. Joint State Broadcaster: Publishes joint states to /joint_states
    2. Mecanum Drive Controller: Controls the robot's mecanum drive movements via ~/cmd_vel

:author: Addison Sears-Collins
:date: November 20, 2024
"""

from launch import LaunchDescription
from launch.actions import RegisterEventHandler, TimerAction
from launch_ros.actions import Node
from launch.event_handlers import OnProcessExit


def generate_launch_description():
    """Generate a launch description for sequentially starting robot controllers.

    The function creates a launch sequence that ensures controllers are started
    in the correct order.

    Returns:
        LaunchDescription: Launch description containing sequenced controller starts
    """
    # Use controller_manager's spawner (waits for the controller manager and
    # retries) instead of one-shot `ros2 control` CLI calls — a fixed delay
    # missed on slow bringups (GUI + house world) and left controllers unloaded.
    start_mecanum_drive_controller_cmd = Node(
        package='controller_manager',
        executable='spawner',
        arguments=['mecanum_drive_controller',
                   '--controller-manager-timeout', '120'],
        output='screen'
    )

    start_joint_state_broadcaster_cmd = Node(
        package='controller_manager',
        executable='spawner',
        arguments=['joint_state_broadcaster',
                   '--controller-manager-timeout', '120'],
        output='screen'
    )

    # Small grace period, then the spawner itself waits as long as needed.
    delayed_start = TimerAction(
        period=5.0,
        actions=[start_joint_state_broadcaster_cmd]
    )

    # Register event handler for sequencing
    load_joint_state_broadcaster_cmd = RegisterEventHandler(
        event_handler=OnProcessExit(
            target_action=start_joint_state_broadcaster_cmd,
            on_exit=[start_mecanum_drive_controller_cmd]))

    # Create and populate the launch description
    ld = LaunchDescription()

    # Add the actions to the launch description in sequence
    ld.add_action(delayed_start)
    ld.add_action(load_joint_state_broadcaster_cmd)

    return ld
