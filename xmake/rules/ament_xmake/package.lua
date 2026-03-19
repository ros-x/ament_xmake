local function _append_unique(out, values)
    if not values then
        return
    end
    for _, value in ipairs(values) do
        local seen = false
        for _, existing in ipairs(out) do
            if existing == value then
                seen = true
                break
            end
        end
        if not seen and value and value ~= "" then
            table.insert(out, value)
        end
    end
end

local function _normalize_ros_dep_args(...)
    local args = {...}
    local opts = {}
    if #args == 0 then
        print("error: add_ros_deps() expects at least one package")
        return {}, {}
    end
    if type(args[#args]) == "table" and #args > 1 then
        opts = args[#args]
        table.remove(args, #args)
    end
    local packages = {}
    if #args == 1 and type(args[1]) == "table" then
        packages = args[1]
    else
        packages = args
    end
    local normalized = {}
    for _, pkg in ipairs(packages) do
        if type(pkg) ~= "string" or pkg == "" then
            print("error: add_ros_deps(): package names must be non-empty strings")
            return {}, {}
        end
        local seen = false
        for _, existing in ipairs(normalized) do
            if existing == pkg then
                seen = true
                break
            end
        end
        if not seen then
            table.insert(normalized, pkg)
        end
    end
    return normalized, opts
end

local function _find_pkg_prefix(pkg)
    local ament_prefix_path = os.getenv("AMENT_PREFIX_PATH") or ""
    for _, prefix in ipairs(path.splitenv(ament_prefix_path)) do
        if os.isfile(path.join(prefix, "share", pkg, "package.xml")) then
            return prefix
        end
    end
    return nil
end

local function _resolve_from_index(pkg, visited, acc)
    if visited[pkg] then
        return
    end
    visited[pkg] = true

    local index = _AMENT_XMAKE_ROS_INDEX or {}
    local meta = index[pkg]
    local prefix = _find_pkg_prefix(pkg)
    if not meta then
        -- ignore meta/buildtool deps not present in generated runtime index
        if prefix then
            local inc_root = path.join(prefix, "include")
            local inc_pkg = path.join(inc_root, pkg)
            if os.isdir(inc_root) then
                _append_unique(acc.include_dirs, {inc_root})
            end
            if os.isdir(inc_pkg) then
                _append_unique(acc.include_dirs, {inc_pkg})
            end
            local lib = path.join(prefix, "lib", "lib" .. pkg .. ".so")
            if os.isfile(lib) then
                _append_unique(acc.link_flags, {lib})
                _append_unique(acc.rpath_dirs, {path.directory(lib)})
            end
        end
        return
    end

    if prefix then
        local inc_root = path.join(prefix, "include")
        local inc_pkg = path.join(prefix, "include", pkg)
        if os.isdir(inc_root) then
            _append_unique(acc.include_dirs, {inc_root})
        end
        if os.isdir(inc_pkg) then
            _append_unique(acc.include_dirs, {inc_pkg})
        end
    end

    _append_unique(acc.include_dirs, meta.include_dirs)
    _append_unique(acc.compile_definitions, meta.compile_definitions)
    _append_unique(acc.link_flags, meta.link_flags)
    _append_unique(acc.rpath_dirs, meta.rpath_dirs)

    for _, dep in ipairs(meta.dependencies or {}) do
        _resolve_from_index(dep, visited, acc)
    end
end

function add_ros_deps(...)
    local packages, opts = _normalize_ros_dep_args(...)
    if #packages == 0 then
        return
    end

    if _AMENT_XMAKE_ROS_INDEX == nil then
        print("error: add_ros_deps(): ROS index not loaded. Build through colcon-xmake or ensure index prelude is included")
        return
    end

    local acc = {
        include_dirs = {},
        compile_definitions = {},
        link_flags = {},
        rpath_dirs = {},
    }
    local ament_prefix_path = os.getenv("AMENT_PREFIX_PATH") or ""
    for _, prefix in ipairs(path.splitenv(ament_prefix_path)) do
        local inc_root = path.join(prefix, "include")
        if os.isdir(inc_root) then
            _append_unique(acc.include_dirs, {inc_root})
            _append_unique(acc.include_dirs, os.dirs(path.join(inc_root, "*")))
        end
    end
    local visited = {}
    for _, pkg in ipairs(packages) do
        _resolve_from_index(pkg, visited, acc)
    end

    if #acc.include_dirs > 0 then
        for _, include_dir in ipairs(acc.include_dirs) do
            if opts.visibility == "public" then
                add_includedirs(include_dir, {public = true})
            else
                add_includedirs(include_dir)
            end
        end
    end

    if #acc.compile_definitions > 0 then
        for _, define in ipairs(acc.compile_definitions) do
            if opts.visibility == "public" then
                add_defines(define, {public = true})
            else
                add_defines(define)
            end
        end
    end

    if #acc.link_flags > 0 then
        for _, flag in ipairs(acc.link_flags) do
            add_ldflags(flag, {force = true})
        end
    end

    if #acc.rpath_dirs > 0 then
        for _, rpath_dir in ipairs(acc.rpath_dirs) do
            add_rpathdirs(rpath_dir)
        end
    end
end

-- Register additional data directories for installation beyond the conventional ones.
-- At parse time, we store entries via environment variable since io may not be available.
-- The on_install handler reads these back.
_AMENT_XMAKE_EXTRA_DATA = _AMENT_XMAKE_EXTRA_DATA or {}

function install_ros_data(subdir, ...)
    local files = {...}
    if #files == 0 then
        print("error: install_ros_data() expects at least one file pattern")
        return
    end
    for _, pattern in ipairs(files) do
        table.insert(_AMENT_XMAKE_EXTRA_DATA, {subdir = subdir, pattern = pattern})
    end
end

-- Register plugin description XML files for installation.
_AMENT_XMAKE_EXTRA_PLUGINS = _AMENT_XMAKE_EXTRA_PLUGINS or {}

function install_ros_plugin(plugin_xml, base_class_pkg)
    if not plugin_xml or not base_class_pkg then
        print("error: install_ros_plugin() expects (plugin_xml_path, base_class_package)")
        return
    end
    table.insert(_AMENT_XMAKE_EXTRA_PLUGINS, {
        xml = plugin_xml,
        base_class_pkg = base_class_pkg,
    })
end

rule("ament_xmake.package")
    on_install(function (target)
        local function mkdir_p(dir)
            os.execv("mkdir", {"-p", dir})
        end

        local function remove_path(path_)
            os.execv("rm", {"-rf", path_})
        end

        local function install_file(src, dst)
            local symlink_install = os.getenv("AMENT_XMAKE_SYMLINK_INSTALL") == "1"
            mkdir_p(path.directory(dst))
            if symlink_install and os.host() == "linux" then
                remove_path(dst)
                os.execv("ln", {"-sfn", src, dst})
            else
                os.cp(src, dst)
            end
        end

        local installdir = target:installdir()
        if not installdir then
            print("error: installdir is not configured; run xmake f --installdir=<dir>")
            return
        end

        local source_dir = os.getenv("AMENT_XMAKE_SOURCE_DIR") or os.projectdir()
        local pkgname = path.filename(source_dir)
        local share_pkg_dir = path.join(installdir, "share", pkgname)
        local marker_dir = path.join(
            installdir, "share", "ament_index", "resource_index", "packages")
        local pkg_state_dir = path.join(share_pkg_dir, ".ament_xmake")
        local pkg_meta_done = path.join(pkg_state_dir, "pkg_meta_done")

        if not os.isfile(pkg_meta_done) then
            mkdir_p(pkg_state_dir)
            local include_dir = path.join(installdir, "include")
            mkdir_p(include_dir)
            local project_include_dir = path.join(source_dir, "include")
            if os.isdir(project_include_dir) then
                os.cp(path.join(project_include_dir, "*"), include_dir)
            end

            local pkgxml = path.join(source_dir, "package.xml")
            mkdir_p(share_pkg_dir)
            if os.isfile(pkgxml) then
                install_file(pkgxml, path.join(share_pkg_dir, "package.xml"))
            end

            mkdir_p(marker_dir)
            io.writefile(path.join(marker_dir, pkgname), "")

            -- Install ROS data files (launch, config, etc.) from install_ros_data() calls
            for _, entry in ipairs(_AMENT_XMAKE_EXTRA_DATA or {}) do
                local matched = os.files(path.join(source_dir, entry.pattern))
                for _, src_file in ipairs(matched) do
                    local dst = path.join(share_pkg_dir, entry.subdir, path.filename(src_file))
                    install_file(src_file, dst)
                end
            end

            -- Auto-install conventional ROS data directories if they exist
            local conventional_dirs = {"launch", "config", "urdf", "meshes", "maps", "worlds", "rviz", "params"}
            for _, subdir in ipairs(conventional_dirs) do
                local src_subdir = path.join(source_dir, subdir)
                if os.isdir(src_subdir) then
                    local files_in_dir = os.files(path.join(src_subdir, "*"))
                    for _, src_file in ipairs(files_in_dir) do
                        local dst = path.join(share_pkg_dir, subdir, path.filename(src_file))
                        install_file(src_file, dst)
                    end
                end
            end

            -- Auto-detect and install plugin description XML files
            -- Scan for XML files containing <library> (pluginlib pattern)
            local plugin_xmls = os.files(path.join(source_dir, "*plugin*.xml"))
            for _, src_xml in ipairs(plugin_xmls) do
                local content = io.readfile(src_xml) or ""
                if content:find("<library") then
                    local dst_xml = path.join(share_pkg_dir, path.filename(src_xml))
                    install_file(src_xml, dst_xml)
                    -- Parse base_class_type to determine the index key
                    -- Try to extract base_class_type from XML
                    local base_pkg = content:match('base_class_type="([^"]+)"')
                    if base_pkg then
                        -- Extract package name from fully qualified type (e.g. rclcpp_components::NodeFactory)
                        local idx_pkg = base_pkg:match("^([^:]+)")
                        if idx_pkg then
                            local pluginlib_index_dir = path.join(
                                installdir, "share", "ament_index", "resource_index",
                                idx_pkg .. "__pluginlib__plugin")
                            mkdir_p(pluginlib_index_dir)
                            io.writefile(
                                path.join(pluginlib_index_dir, pkgname),
                                "share/" .. pkgname .. "/" .. path.filename(src_xml) .. "\n")
                        end
                    end
                end
            end

            io.writefile(pkg_meta_done, "")
        end

        local include_dir = path.join(installdir, "include")
        local kind = target:get("kind")
        local targetfile = target:targetfile()
        local installed_lib_path = nil
        if targetfile and os.isfile(targetfile) then
            if kind == "binary" then
                local dst = path.join(installdir, "lib", pkgname, path.filename(targetfile))
                install_file(targetfile, dst)
            else
                local dst = path.join(installdir, "lib", path.filename(targetfile))
                install_file(targetfile, dst)
                installed_lib_path = dst
            end
        end

        -- Generate CMake package config from library targets
        -- Each library target writes a cmake fragment; the top-level Config.cmake
        -- includes all fragments so downstream find_package() works for multi-target packages.
        if kind == "binary" then
            return
        end

        local cmake_dir = path.join(installdir, "share", pkgname, "cmake")
        mkdir_p(cmake_dir)

        -- Determine the cmake target name: use basename if set, otherwise target name
        local lib_filename = path.filename(targetfile or "")
        local cmake_target_name = target:name()
        -- Extract the library name from filename (e.g. libfoo.so -> foo, libfoo.a -> foo)
        if lib_filename ~= "" then
            local base = lib_filename:match("^lib(.+)%.so") or lib_filename:match("^lib(.+)%.a")
            if base then
                cmake_target_name = base
            end
        end

        local is_shared = kind == "shared"
        local lib_type = is_shared and "SHARED" or "STATIC"

        -- Write per-target cmake fragment
        local fragment_name = cmake_target_name .. "-target.cmake"
        local fragment_path = path.join(cmake_dir, fragment_name)
        local lines = {}
        table.insert(lines, "# Auto-generated by ament_xmake for target: " .. cmake_target_name)
        if installed_lib_path then
            table.insert(lines, "if(NOT TARGET " .. pkgname .. "::" .. cmake_target_name .. ")")
            table.insert(lines, "  add_library(" .. pkgname .. "::" .. cmake_target_name .. " " .. lib_type .. " IMPORTED)")
            table.insert(lines, "  set_target_properties(" .. pkgname .. "::" .. cmake_target_name .. " PROPERTIES")
            table.insert(lines, "    IMPORTED_LOCATION \"" .. installed_lib_path .. "\"")
            if is_shared then
                table.insert(lines, "    IMPORTED_SONAME \"" .. lib_filename .. "\"")
            end
            table.insert(lines, "    INTERFACE_INCLUDE_DIRECTORIES \"" .. include_dir .. "\"")
            table.insert(lines, "    INTERFACE_LINK_DIRECTORIES \"" .. path.join(installdir, "lib") .. "\")")
            table.insert(lines, "endif()")
        end
        io.writefile(fragment_path, table.concat(lines, "\n") .. "\n")

        -- Write or update top-level Config.cmake that includes all fragments
        -- and provides the legacy variables
        local cfg = path.join(cmake_dir, pkgname .. "Config.cmake")
        local cfg_lines = {}
        cfg_lines[1] = "# Auto-generated by ament_xmake"
        cfg_lines[2] = "set(" .. pkgname .. "_FOUND TRUE)"
        cfg_lines[3] = "set(" .. pkgname .. "_INCLUDE_DIRS \"" .. include_dir .. "\")"
        cfg_lines[4] = "set(" .. pkgname .. "_LIBRARIES \"\")"
        cfg_lines[5] = "set(" .. pkgname .. "_LIBRARY_DIRS \"" .. path.join(installdir, "lib") .. "\")"
        cfg_lines[6] = ""
        cfg_lines[7] = "# Include all target fragments"
        cfg_lines[8] = "get_filename_component(_dir \"${CMAKE_CURRENT_LIST_FILE}\" PATH)"
        cfg_lines[9] = "file(GLOB _fragments \"${_dir}/*-target.cmake\")"
        cfg_lines[10] = "foreach(_f ${_fragments})"
        cfg_lines[11] = "  include(${_f})"
        cfg_lines[12] = "endforeach()"
        cfg_lines[13] = "unset(_fragments)"
        cfg_lines[14] = "unset(_dir)"
        cfg_lines[15] = ""
        -- Provide a default alias: <pkg>::<pkg> pointing to the primary library
        -- Prefer shared library, fall back to static
        cfg_lines[16] = "# Default alias target"
        cfg_lines[17] = "if(NOT TARGET " .. pkgname .. "::" .. pkgname .. ")"
        cfg_lines[18] = "  # Try to find the best matching target"
        local shared_lib = path.join(installdir, "lib", "lib" .. pkgname .. ".so")
        local static_lib = path.join(installdir, "lib", "lib" .. pkgname .. ".a")
        cfg_lines[19] = "  if(EXISTS \"" .. shared_lib .. "\")"
        cfg_lines[20] = "    add_library(" .. pkgname .. "::" .. pkgname .. " SHARED IMPORTED)"
        cfg_lines[21] = "    set_target_properties(" .. pkgname .. "::" .. pkgname .. " PROPERTIES"
        cfg_lines[22] = "      IMPORTED_LOCATION \"" .. shared_lib .. "\""
        cfg_lines[23] = "      INTERFACE_INCLUDE_DIRECTORIES \"" .. include_dir .. "\""
        cfg_lines[24] = "      INTERFACE_LINK_DIRECTORIES \"" .. path.join(installdir, "lib") .. "\")"
        cfg_lines[25] = "  elseif(EXISTS \"" .. static_lib .. "\")"
        cfg_lines[26] = "    add_library(" .. pkgname .. "::" .. pkgname .. " STATIC IMPORTED)"
        cfg_lines[27] = "    set_target_properties(" .. pkgname .. "::" .. pkgname .. " PROPERTIES"
        cfg_lines[28] = "      IMPORTED_LOCATION \"" .. static_lib .. "\""
        cfg_lines[29] = "      INTERFACE_INCLUDE_DIRECTORIES \"" .. include_dir .. "\""
        cfg_lines[30] = "      INTERFACE_LINK_DIRECTORIES \"" .. path.join(installdir, "lib") .. "\")"
        cfg_lines[31] = "  endif()"
        cfg_lines[32] = "endif()"
        io.writefile(cfg, table.concat(cfg_lines, "\n") .. "\n")
    end)
