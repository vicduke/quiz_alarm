allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 1. THE FIX: Register the hook BEFORE Flutter forces the evaluation
subprojects {
    if (!project.state.executed) {
        project.afterEvaluate {
            if (project.plugins.hasPlugin("com.android.library")) {
                project.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                    compileSdk = 36
                }
            }
        }
    }
}

// 2. FLUTTER'S TRIGGER: Must stay at the very bottom
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}