package com.kivo.app

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * Strategy:
     *  1. Try Flutter's standard auto-registration (GeneratedPluginRegistrant).
     *     On real devices this always succeeds — all plugins registered, done.
     *  2. If auto-registration throws a Throwable (e.g. FFmpegKit raises
     *     UnsatisfiedLinkError on some emulators), fall back to registering
     *     every plugin individually inside its own try-catch(Throwable) block.
     *  3. After a fallback, null out the FFmpegKit channel handler so Dart
     *     receives a catchable MissingPluginException instead of a native crash.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        try {
            // Fast path — works on real devices and most emulators.
            super.configureFlutterEngine(flutterEngine)
            return
        } catch (t: Throwable) {
            Log.w("MainActivity", "Auto plugin registration failed ($t). Using safe fallback.")
        }

        // Slow path: register each plugin individually so a single failure
        // (typically FFmpegKit's native library) does not block the others.
        var ffmpegKitFailed = false
        val registrations = listOf<Pair<String, () -> Unit>>(
            "ffmpeg_kit_flutter_new" to {
                flutterEngine.plugins.add(
                    com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin()
                )
            },
            "file_picker" to {
                flutterEngine.plugins.add(
                    com.mr.flutter.plugin.filepicker.FilePickerPlugin()
                )
            },
            "flutter_image_compress" to {
                flutterEngine.plugins.add(
                    com.fluttercandies.flutter_image_compress.ImageCompressPlugin()
                )
            },
            "flutter_plugin_android_lifecycle" to {
                flutterEngine.plugins.add(
                    io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin()
                )
            },
            "package_info_plus" to {
                flutterEngine.plugins.add(
                    dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin()
                )
            },
            "path_provider_android" to {
                flutterEngine.plugins.add(
                    io.flutter.plugins.pathprovider.PathProviderPlugin()
                )
            },
            "printing" to {
                flutterEngine.plugins.add(
                    net.nfet.flutter.printing.PrintingPlugin()
                )
            },
        )

        for ((name, register) in registrations) {
            try {
                register()
            } catch (t: Throwable) {
                Log.e("MainActivity", "Failed to register plugin '$name': $t")
                if (name == "ffmpeg_kit_flutter_new") ffmpegKitFailed = true
            }
        }

        // If FFmpegKit's native library failed to load, clear its channel so
        // Dart receives a catchable MissingPluginException instead of a native crash.
        if (ffmpegKitFailed) {
            val messenger = flutterEngine.dartExecutor.binaryMessenger
            MethodChannel(messenger, "flutter.arthenica.com/ffmpeg_kit")
                .setMethodCallHandler(null)
            Log.w("MainActivity", "FFmpegKit disabled — video compression unavailable on this device.")
        }
    }
}
