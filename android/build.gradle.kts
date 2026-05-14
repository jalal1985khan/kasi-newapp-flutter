buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
    configurations.all {
        resolutionStrategy {
            force("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
            force("org.jetbrains.kotlin:kotlin-stdlib:2.1.0")
            force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.1.0")
            force("androidx.browser:browser:1.8.0")
            force("androidx.core:core:1.13.1")
            force("androidx.core:core-ktx:1.13.1")
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

subprojects {
    plugins.withType<org.jetbrains.kotlin.gradle.plugin.KotlinBasePluginWrapper> {
        project.plugins.removeIf { it is org.jetbrains.kotlin.gradle.internal.AndroidExtensionsSubpluginIndicator }
    }
    plugins.withId("kotlin-android-extensions") {
        project.plugins.remove(this)
    }
    plugins.withType<com.android.build.gradle.BasePlugin> {
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            @Suppress("DEPRECATION")
            kotlinOptions {
                // Automatically match Kotlin JVM target to the Java target
                val javaVersion = project.extensions.getByType(com.android.build.gradle.BaseExtension::class.java)
                    .compileOptions.targetCompatibility.toString()
                
                if (javaVersion == "1.8") {
                    jvmTarget = "1.8"
                } else if (javaVersion == "17") {
                    jvmTarget = "17"
                }
            }
        }
    }
}

subprojects {
    if (project.name == "twilio_programmable_video") {
        // Set compileSdkVersion before evaluation to satisfy modern AGP
        project.extensions.extraProperties.set("compileSdkVersion", 34)
        
        project.plugins.withId("com.android.library") {
            val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            android?.apply {
                compileSdkVersion(34)
                namespace = "com.twilio.twilio_programmable_video"
            }
            
            // Fix for redundant package attribute in modern AGP
            project.tasks.matching { it.name.contains("process") && it.name.contains("Manifest") }.configureEach {
                doFirst {
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val content = manifestFile.readText()
                        if (content.contains("package=")) {
                            println("🔧 [Gradle] Stripping redundant package attribute from twilio manifest")
                            manifestFile.writeText(content.replace(Regex("package=\"[^\"]*\""), ""))
                        }
                    }
                }
            }

            // Force remove the problematic plugin from the target project directly
            project.afterEvaluate {
                project.plugins.removeIf { 
                    it.javaClass.name.contains("AndroidExtensions") || 
                    it.toString().contains("kotlin-android-extensions") 
                }
            }

            // Disable strict Kotlin checks for legacy plugin
            project.tasks.matching { it.name == "checkKotlinGradlePluginConfigurationErrors" }.configureEach {
                enabled = false
            }

            // Use compileOnly to avoid duplicate class errors in release builds
            project.dependencies.add("compileOnly", "io.flutter:flutter_embedding_debug:1.0.0-42d3d75a56efe1a2e9902f52dc8006099c45d937")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
