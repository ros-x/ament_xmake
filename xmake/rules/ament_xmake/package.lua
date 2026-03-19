rule("ament_xmake.package")
    on_install(function (target)
        local installdir = target:installdir()
        if not installdir then
            raise("installdir is not configured; run xmake f --installdir=<dir>")
        end

        local pkgname = path.filename(os.projectdir())
        local pkgxml = path.join(os.projectdir(), "package.xml")
        os.mkdir(path.join(installdir, "share", pkgname))
        if os.isfile(pkgxml) then
            os.cp(pkgxml, path.join(installdir, "share", pkgname, "package.xml"))
        end

        local marker_dir = path.join(installdir, "share", "ament_index", "resource_index", "packages")
        os.mkdir(marker_dir)
        io.writefile(path.join(marker_dir, pkgname), "")

        -- Generate a minimal CMake package config so downstream
        -- find_package(<pkg> CONFIG) can resolve the package.
        local cmake_dir = path.join(installdir, "share", pkgname, "cmake")
        os.mkdir(cmake_dir)
        local cfg = path.join(cmake_dir, pkgname .. "Config.cmake")
        if not os.isfile(cfg) then
            io.writefile(cfg, "set(" .. pkgname .. "_FOUND TRUE)\n")
        end
    end)
