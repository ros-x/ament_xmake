# ament_xmake

[![CI](https://github.com/ros-x/ament_xmake/actions/workflows/ci.yml/badge.svg)](https://github.com/ros-x/ament_xmake/actions/workflows/ci.yml)

ROS 2 rule package that enables building ROS 2 packages with [xmake](https://xmake.io/).
It provides xmake rules and helpers so that xmake-based packages follow standard ament
install conventions and integrate seamlessly with the ROS 2 build ecosystem via
[colcon-xmake](https://github.com/ros-x/colcon-xmake).

## Requirements

- **ROS 2 Jazzy** (or later)
- **[xmake](https://xmake.io/)** build system

## Installation

`ament_xmake` is a standard ROS 2 package. Clone it into a colcon workspace and build:

```bash
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src
git clone https://github.com/ros-x/ament_xmake.git
cd ~/ros2_ws
colcon build --packages-select ament_xmake
source install/setup.bash
```

You will also need [colcon-xmake](https://github.com/ros-x/colcon-xmake) installed so
that `colcon build` knows how to drive xmake-based packages.

## Intended package usage

```lua
add_rules("ament_xmake.package")

target("my_node")
    set_kind("binary")
    add_files("src/my_node.cpp")
    add_ros_deps("rclcpp", "geometry_msgs")
```

The rule is expected to ensure ROS package install conventions:
- install `package.xml` to `share/<pkg>/package.xml`
- install ament index marker to `share/ament_index/resource_index/packages/<pkg>`
- generate minimal `share/<pkg>/cmake/<pkg>Config.cmake` for downstream `find_package(... CONFIG)`
- install built artifacts to ROS-style layout (e.g. `lib/`, `lib/<pkg>/`)
- export imported target `<pkg>::<pkg>` when a library artifact exists
- provide `add_ros_deps(...)` to resolve ROS package include/link flags via CMake export metadata

## Constraints

- For deterministic config export, the primary library target should be named the same as the package.
- In `--symlink-install` mode the plugin sets `AMENT_XMAKE_SYMLINK_INSTALL=1` so install steps prefer symlinks on Linux.

## Docs

- `docs/RULE_SPEC.md`
- `docs/SYMLINK_INSTALL.md`
- `CHANGELOG.md`

## Related projects

- [ros-x](https://github.com/ros-x) — GitHub organization for ROS 2 + xmake tooling
- [colcon-xmake](https://github.com/ros-x/colcon-xmake) — colcon build verb extension for xmake

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
