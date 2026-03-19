# ament_xmake

ROS 2 rule package for xmake-based packages.

## Intended package usage

```lua
add_rules("ament_xmake.package")
```

The rule is expected to ensure ROS package install conventions:
- install `package.xml` to `share/<pkg>/package.xml`
- install ament index marker to `share/ament_index/resource_index/packages/<pkg>`
