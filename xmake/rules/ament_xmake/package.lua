rule("ament_xmake.package")
    set_description("Install conventions for ROS 2 ament_xmake packages")

    on_install(function (target)
        local installdir = target:installdir()
        if not installdir then
            raise("installdir is not configured; run xmake f --installdir=<dir>")
        end

        local pkgname = target:pkgname() or target:name()
        local pkgxml = path.join(os.projectdir(), "package.xml")
        if os.isfile(pkgxml) then
            os.cp(pkgxml, path.join(installdir, "share", pkgname, "package.xml"))
        end

        local marker_dir = path.join(installdir, "share", "ament_index", "resource_index", "packages")
        os.mkdir(marker_dir)
        io.writefile(path.join(marker_dir, pkgname), "")
    end)
