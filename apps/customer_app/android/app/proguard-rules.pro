# Keep Flutter plugin code intact in release builds. Without this, R8 strips methods the
# plugins call through platform channels (e.g. shared_preferences' getAll), which crashes on start.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.baseflow.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class kotlinx.coroutines.** { *; }
# Plugins called from Dart through JNI look up methods by exact type names
# (e.g. kotlin.coroutines.Continuation), so Kotlin class names must not be renamed.
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlinx.coroutines.**
-dontwarn com.google.android.play.core.**
