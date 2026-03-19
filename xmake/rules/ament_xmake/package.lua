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

        -- Generate CMake package config from the primary package library target
        -- so downstream find_package(<pkg> CONFIG) can resolve and link
        -- deterministically for multi-target projects.
        if kind == "binary" then
            return
        end

        local cmake_dir = path.join(installdir, "share", pkgname, "cmake")
        mkdir_p(cmake_dir)
        local cfg = path.join(cmake_dir, pkgname .. "Config.cmake")
        local should_emit = false
        if target:name() == pkgname then
            should_emit = true
        elseif not os.isfile(cfg) then
            -- fallback for global rule mode when no target matches pkg name
            should_emit = true
        end
        if not should_emit then
            return
        end

        local static_lib = path.join(
            installdir, "lib", "lib" .. target:name() .. ".a")
        local shared_lib = path.join(
            installdir, "lib", "lib" .. target:name() .. ".so")
        local lines = {}
        table.insert(lines, "set(" .. pkgname .. "_FOUND TRUE)")
        table.insert(lines, "set(" .. pkgname .. "_INCLUDE_DIR \"" .. include_dir .. "\")")
        table.insert(lines, "set(_" .. pkgname .. "_lib \"\")")
        if installed_lib_path then
            table.insert(lines, "set(_" .. pkgname .. "_lib \"" .. installed_lib_path .. "\")")
        end
        table.insert(lines, "if(NOT _" .. pkgname .. "_lib AND EXISTS \"" .. shared_lib .. "\")")
        table.insert(lines, "  set(_" .. pkgname .. "_lib \"" .. shared_lib .. "\")")
        table.insert(lines, "elseif(NOT _" .. pkgname .. "_lib AND EXISTS \"" .. static_lib .. "\")")
        table.insert(lines, "  set(_" .. pkgname .. "_lib \"" .. static_lib .. "\")")
        table.insert(lines, "endif()")
        table.insert(lines, "if(NOT TARGET " .. pkgname .. "::" .. pkgname .. " AND _" .. pkgname .. "_lib)")
        table.insert(lines, "  add_library(" .. pkgname .. "::" .. pkgname .. " UNKNOWN IMPORTED)")
        table.insert(lines, "  set_target_properties(" .. pkgname .. "::" .. pkgname .. " PROPERTIES")
        table.insert(lines, "    IMPORTED_LOCATION \"${_" .. pkgname .. "_lib}\"")
        table.insert(lines, "    INTERFACE_INCLUDE_DIRECTORIES \"" .. include_dir .. "\")")
        table.insert(lines, "endif()")
        io.writefile(cfg, table.concat(lines, "\n") .. "\n")
    end)
