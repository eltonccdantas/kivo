# Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# ffmpeg_kit_flutter_new (com.antonkarpenko repackage)
-keep class com.antonkarpenko.ffmpegkit.** { *; }
# Also keep the original arthenica package used internally by the native lib
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**

# flutter_image_compress
-keep class com.fluttercandies.flutter_image_compress.** { *; }

# printing / pdf
-keep class net.nfet.flutter.printing.** { *; }

# package_info_plus
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Keep all Flutter plugin registrants
-keep class * extends io.flutter.plugin.common.PluginRegistry { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }

# Flutter Play Store deferred components — not used by this app
-dontwarn com.google.android.play.core.**
