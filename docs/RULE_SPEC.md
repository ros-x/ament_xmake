# ament_xmake Rule Spec

Rule name: `ament_xmake.package`

## Responsibilities

- install package manifest to `share/<pkg>/package.xml`
- create ament index marker under `share/ament_index/resource_index/packages/<pkg>`
- install artifacts to ROS-style directories
- generate `share/<pkg>/cmake/<pkg>Config.cmake`
- export imported target `<pkg>::<pkg>` for package primary library target

## Rule discovery

Preferred path:
- `colcon-xmake` injects `AMENT_XMAKE_RULE_FILE` into xmake command environment.
- package `xmake.lua` should load that file first.

Fallback path:
- scan `AMENT_PREFIX_PATH` for `share/ament_xmake/xmake/rules/ament_xmake/package.lua`.

## Deterministic export rule

Only the target named exactly as package name emits config export data.
