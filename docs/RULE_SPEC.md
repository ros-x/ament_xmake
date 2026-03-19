# ament_xmake Rule Spec

Rule name: `ament_xmake.package`

## Usage modes

Both are supported:
- global mode: `add_rules("ament_xmake.package")` at file scope
- target mode: `add_rules("ament_xmake.package")` inside target block

Implementation uses idempotent package-level actions to avoid duplicate installs in global mode.

## Responsibilities

- install package manifest to `share/<pkg>/package.xml`
- create ament index marker under `share/ament_index/resource_index/packages/<pkg>`
- install artifacts to ROS-style directories
- generate `share/<pkg>/cmake/<pkg>Config.cmake`
- export imported target `<pkg>::<pkg>` for package primary library target

## Rule discovery

Preferred path:
- `colcon-xmake` generates an internal xmake entry file that includes the rule and then includes package `xmake.lua`.
- package `xmake.lua` can simply call `add_rules("ament_xmake.package")`.

Fallback path:
- scan `AMENT_PREFIX_PATH` for `share/ament_xmake/xmake/rules/ament_xmake/package.lua`.

## Deterministic export rule

Only the target named exactly as package name emits config export data.
