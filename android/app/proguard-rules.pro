# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# ffmpeg_kit
-keep class com.arthenica.ffmpegkit.** { *; }

# permission_handler (removed from app but kept in case transitive dep uses it)
-keep class com.baseflow.permissionhandler.** { *; }

# printing / pdf
-keep class com.example.printing.** { *; }

# Keep all Flutter plugin registrants
-keep class * extends io.flutter.plugin.common.PluginRegistry { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }

# Flutter Play Store deferred components — not used by this app, suppress missing-class errors
-dontwarn com.google.android.play.core.**
