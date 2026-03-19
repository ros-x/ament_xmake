# ament_xmake Rule Spec

Rule name: `ament_xmake.package`

## Responsibilities

- install package manifest to `share/<pkg>/package.xml`
- create ament index marker under `share/ament_index/resource_index/packages/<pkg>`
- install artifacts to ROS-style directories
- generate `share/<pkg>/cmake/<pkg>Config.cmake`
- export imported target `<pkg>::<pkg>` for package primary library target

## Deterministic export rule

Only the target named exactly as package name emits config export data.
