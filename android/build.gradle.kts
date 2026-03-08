// android/build.gradle.kts
plugins {
    kotlin("android") apply false
    id("com.android.application") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://storage.googleapis.com/download.flutter.io")
        }
        maven {
            url = uri("http://download.flutter.io")
            isAllowInsecureProtocol = true
        }
        // 可选国内镜像
        maven { url = uri("https://repo.flutter-io.cn/download/flutter/io") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/maven-public") }
    }
    // Ensure UTF-8 for all Java compile tasks
    tasks.withType<JavaCompile>().configureEach {
        options.encoding = "UTF-8"
    }
}

rootProject.layout.buildDirectory = rootProject.layout.projectDirectory.dir("../build")
subprojects {
    project.layout.buildDirectory = rootProject.layout.buildDirectory.dir(project.name)
    evaluationDependsOn(":app")

    afterEvaluate {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            kotlinOptions {
                // Kotlin 2.2+ no longer supports languageVersion/apiVersion 1.6.
                // Some Flutter plugins (e.g. sentry_flutter) still pin 1.6, so bump to 1.8.
                if (languageVersion == "1.6") languageVersion = "1.8"
                if (apiVersion == "1.6") apiVersion = "1.8"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
