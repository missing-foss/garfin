allprojects {
    repositories {
        google()
        mavenCentral()

        // JitPack, for `com.github.woheller69:FreeDroidWarn` only.
        //
        // JitPack builds from a git tag on demand rather than serving a
        // publisher-signed artifact, so it is a weaker supply-chain guarantee
        // than the two above and is deliberately not opened for everything:
        // `includeGroup` means anything NOT that group resolves here exactly as
        // it did before this line existed, and a typo in a coordinate fails to
        // resolve rather than silently reaching a different builder.
        //
        // It is upstream's only publication route -- the library is not on
        // Maven Central -- so the choice was this or vendoring the source.
        maven {
            url = uri("https://jitpack.io")
            content { includeGroup("com.github.woheller69") }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
