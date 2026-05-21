// Root build script. No plugins applied at the root level.
// Each service-version module brings its own plugins, dependencies, and source.

allprojects {
    repositories {
        mavenCentral()
    }
}

subprojects {
    // When a subproject applies the java plugin, pin it to Java 21.
    plugins.withId("java") {
        extensions.configure<JavaPluginExtension> {
            toolchain {
                languageVersion.set(JavaLanguageVersion.of(21))
            }
        }
    }
}
