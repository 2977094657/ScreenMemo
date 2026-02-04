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
        // 启用 desugaring 以支持 Java 8+ 语言/库特性（满足 flutter_local_notifications 要求）
        isCoreLibraryDesugaringEnabled = true
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

    // 启用核心库 desugaring（满足 flutter_local_notifications 的 AAR 要求）
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // OkHttp：用于每日总结/分段上传等 HTTP 调用
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Chucker：OkHttp 抓包（Debug 可视化，Release no-op）
    debugImplementation("com.github.chuckerteam.chucker:library:4.0.0")
    releaseImplementation("com.github.chuckerteam.chucker:library-no-op:4.0.0")

    // ML Kit: 中文文本识别（离线模型随 APK 打包）
    implementation("com.google.mlkit:text-recognition-chinese:16.0.0")

    // WorkManager：后台每日总结生成
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // XLog：高性能日志（控制台/多 Printer，可替代原生 Log.* 控制台输出）
    implementation("com.elvishew:xlog:1.11.1")

    // 协程：后台事件处理与流式更新
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // Lifecycle：为服务和 Application 提供协程生命周期支持
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-service:2.8.4")

    // Unit tests
    testImplementation("junit:junit:4.13.2")
    testImplementation("io.mockk:mockk:1.13.12")
    // Use JVM org.json to avoid "not mocked" stubs in local unit tests
    testImplementation("org.json:json:20231013")
}
