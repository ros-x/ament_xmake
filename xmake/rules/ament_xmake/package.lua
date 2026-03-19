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
            raise("installdir is not configured; run xmake f --installdir=<dir>")
        end

        local pkgname = path.filename(os.projectdir())
        local share_pkg_dir = path.join(installdir, "share", pkgname)
        local marker_dir = path.join(
            installdir, "share", "ament_index", "resource_index", "packages")
        local pkg_state_dir = path.join(share_pkg_dir, ".ament_xmake")
        local pkg_meta_done = path.join(pkg_state_dir, "pkg_meta_done")

        if not os.isfile(pkg_meta_done) then
            mkdir_p(pkg_state_dir)
            local include_dir = path.join(installdir, "include")
            mkdir_p(include_dir)
            local project_include_dir = path.join(os.projectdir(), "include")
            if os.isdir(project_include_dir) then
                os.cp(path.join(project_include_dir, "*"), include_dir)
            end

            local pkgxml = path.join(os.projectdir(), "package.xml")
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
