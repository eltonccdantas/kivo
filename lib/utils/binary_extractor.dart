import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Extracts the bundled FFmpeg binary from assets to the app support directory
/// on first run (desktop only). Caches the result for subsequent calls.
class BinaryExtractor {
  static String? _cachedPath;

  static Future<String> ffmpegPath() async {
    if (_cachedPath != null) return _cachedPath!;

    final supportDir = await getApplicationSupportDirectory();
    final binName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    final targetFile = File('${supportDir.path}/kivo_bin/$binName');

    String assetPath;
    if (Platform.isMacOS) {
      assetPath = 'assets/bin/macos/ffmpeg';
    } else if (Platform.isWindows) {
      assetPath = 'assets/bin/windows/ffmpeg.exe';
    } else {
      assetPath = 'assets/bin/linux/ffmpeg';
    }

    if (!await targetFile.exists()) {
      try {
        final data = await rootBundle.load(assetPath);
        // Only extract if it's a real binary (placeholder files are <1 KB)
        if (data.lengthInBytes > 1024 * 1024) {
          await targetFile.parent.create(recursive: true);
          await targetFile.writeAsBytes(
            data.buffer.asUint8List(),
            flush: true,
          );
          if (!Platform.isWindows) {
            await Process.run('chmod', ['+x', targetFile.path]);
          }
        }
      } catch (_) {}
    }

    if (await targetFile.exists() && await targetFile.length() > 1024 * 1024) {
      _cachedPath = targetFile.path;
    } else {
      // Fall back to system FFmpeg
      _cachedPath = 'ffmpeg';
    }

    return _cachedPath!;
  }
}
