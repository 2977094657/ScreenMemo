// android/build.gradle.kts
plugins {
    kotlin("android") apply false
    id("com.android.application") apply false
}

buildscript {
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
    dependencies {
        classpath("com.android.tools.build:gradle:7.3.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.7.10")
    }
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
