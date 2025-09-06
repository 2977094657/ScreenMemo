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

