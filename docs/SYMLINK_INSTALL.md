# Symlink Install Behavior

When `colcon build --symlink-install` is used, plugin sets:
- `AMENT_XMAKE_SYMLINK_INSTALL=1`

`ament_xmake.package` then prefers symlink creation for install artifacts on Linux.

This behavior is intended to match ROS developer workflows that rely on fast iterative rebuilds.
