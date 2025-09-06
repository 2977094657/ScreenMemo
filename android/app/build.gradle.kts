import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fqyw.screen_memo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"
    
    buildFeatures {
        aidl = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fqyw.screen_memo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Inject Umeng placeholders from local.properties/env for manifest
        val props = Properties().apply {
            val f = rootProject.file("local.properties")
            if (f.exists()) f.inputStream().use { load(it) }
        }
        val umengAppKey = (props.getProperty("UMENG_APPKEY")
            ?: System.getenv("UMENG_APPKEY")
            ?: "")
        val umengChannel = (props.getProperty("UMENG_CHANNEL")
            ?: System.getenv("UMENG_CHANNEL")
            ?: "official")
        manifestPlaceholders["UMENG_APPKEY"] = umengAppKey
        manifestPlaceholders["UMENG_CHANNEL"] = umengChannel
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Satisfy Flutter deferred components references during R8 shrinking
    implementation("com.google.android.play:core:1.10.3")

    // Umeng Common SDK (Analytics base) + ASMS + APM (Crash/ANR/卡顿/性能)
    implementation("com.umeng.umsdk:common:9.8.5")
    implementation("com.umeng.umsdk:asms:1.8.7.2")
    implementation("com.umeng.umsdk:apm:2.0.4")

    // OkHttp (required by Umeng APM's EFS net monitor classes referenced at runtime)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
