# Keep Flutter and Dart entry points
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Kotlin metadata
-keep class kotlin.Metadata { *; }

# Keep classes with @Keep
-keep @androidx.annotation.Keep class * { *; }
-keep class * { @androidx.annotation.Keep *; }

# Reduce warnings
-dontwarn java.lang.invoke.*
-dontwarn org.codehaus.mojo.animal_sniffer.*

# OkHttp（每日总结等 HTTP 请求）
-dontwarn okhttp3.**

# ML Kit Text Recognition keep rules
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_chinese.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_common.**
-dontwarn com.google.android.gms.internal.mlkit_vision_text_common.**
-dontwarn com.google.android.gms.internal.mlkit_vision_text_chinese.**

