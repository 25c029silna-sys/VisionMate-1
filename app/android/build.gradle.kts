allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Build directory configuration on system temp drive to prevent drive H filesystem lock issues
val localTempBuildDir = File(System.getProperty("java.io.tmpdir"), "visionmate_build")
rootProject.layout.buildDirectory.set(localTempBuildDir)
subprojects {
    project.layout.buildDirectory.set(rootProject.layout.buildDirectory.map { it.dir(project.name) })
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    plugins.withId("com.android.application") {
        configure<com.android.build.api.dsl.ApplicationExtension> {
            defaultConfig {
                minSdk = 24
            }
        }
    }
    plugins.withId("com.android.library") {
        configure<com.android.build.api.dsl.LibraryExtension> {
            defaultConfig {
                minSdk = 24
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

