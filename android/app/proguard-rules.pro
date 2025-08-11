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

