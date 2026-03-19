package com.example.kivo

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Register each Flutter plugin individually so that a native library
     * failure in one plugin (e.g. FFmpegKit UnsatisfiedLinkError on some
     * emulators) does not prevent the remaining plugins from registering.
     *
     * If FFmpegKit fails, we also null-out its channel handlers so Dart
     * receives a graceful MissingPluginException instead of a native crash.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        val registrations = listOf<Pair<String, () -> Unit>>(
            "ffmpeg_kit_flutter_new" to {
                flutterEngine.plugins.add(com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin())
            },
            "file_picker" to {
                flutterEngine.plugins.add(com.mr.flutter.plugin.filepicker.FilePickerPlugin())
            },
            "flutter_plugin_android_lifecycle" to {
                flutterEngine.plugins.add(
                    io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin()
                )
            },
            "package_info_plus" to {
                flutterEngine.plugins.add(dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin())
            },
            "path_provider_android" to {
                flutterEngine.plugins.add(io.flutter.plugins.pathprovider.PathProviderPlugin())
            },
            "printing" to {
                flutterEngine.plugins.add(net.nfet.flutter.printing.PrintingPlugin())
            },
        )

        var ffmpegKitFailed = false
        for ((name, register) in registrations) {
            try {
                register()
            } catch (t: Throwable) {
                Log.e("MainActivity", "Failed to register plugin $name: $t")
                if (name == "ffmpeg_kit_flutter_new") ffmpegKitFailed = true
            }
        }

        // If FFmpegKit's native library failed to load, clear any partially
        // registered channel handlers so Dart gets MissingPluginException
        // (a catchable Dart error) instead of a native NoClassDefFoundError crash.
        if (ffmpegKitFailed) {
            val messenger = flutterEngine.dartExecutor.binaryMessenger
            MethodChannel(messenger, "flutter.arthenica.com/ffmpeg_kit")
                .setMethodCallHandler(null)
        }
    }
}
