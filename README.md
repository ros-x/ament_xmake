# ament_xmake

ROS 2 rule package for xmake-based packages.

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
