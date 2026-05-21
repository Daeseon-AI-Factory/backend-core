rootProject.name = "backend-core"

// Discover service-version modules dynamically.
// Service branches add their module by creating its directory under
// services/<svc>/v<N>-<name>/ — no edit to this file is needed.
file("services").listFiles()?.filter { it.isDirectory }?.forEach { svc ->
    svc.listFiles()?.filter { it.isDirectory && it.name.startsWith("v") }?.forEach { version ->
        val moduleName = ":services:${svc.name}:${version.name}"
        include(moduleName)
        project(moduleName).projectDir = version
    }
}

// Same for pkg modules. A module folder either contains v* subdirectories
// (multi-version) or is itself the module (single-version).
file("pkg").listFiles()?.filter { it.isDirectory }?.forEach { mod ->
    val versionDirs = mod.listFiles()?.filter { it.isDirectory && it.name.startsWith("v") }
    if (versionDirs != null && versionDirs.isNotEmpty()) {
        versionDirs.forEach { v ->
            include(":pkg:${mod.name}:${v.name}")
            project(":pkg:${mod.name}:${v.name}").projectDir = v
        }
    } else {
        include(":pkg:${mod.name}")
    }
}
