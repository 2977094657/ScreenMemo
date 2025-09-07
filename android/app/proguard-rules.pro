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

# Umeng SDK keep rules (APM/Analytics)
-keep class com.umeng.** { *; }
-dontwarn com.umeng.**

# EFS SDK (Umeng APM internal net monitor)
-keep class com.efs.** { *; }
-dontwarn com.efs.**

# OkHttp (ensure types are retained if referenced)
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

