import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import '../utils/binary_extractor.dart';

class VideoService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
  }) async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      // Mobile: FFmpeg subprocess is not available on sandboxed iOS/Android.
      // Copy the file and inform the user.
      await input.copy(outputPath);
      final bytes = await input.length();
      return CompressionResult(
        outputPath: outputPath,
        originalBytes: bytes,
        compressedBytes: bytes,
        improved: false,
        note:
            'Video compression via FFmpeg is only available on desktop platforms. '
            'File copied as-is.',
      );
    }

    return _compressDesktop(input, outputPath, onProgress: onProgress);
  }

  Future<CompressionResult> _compressDesktop(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
  }) async {
    final originalBytes = await input.length();
    onProgress?.call(0.02);

    final ffmpeg = await BinaryExtractor.ffmpegPath();
    final totalSeconds = await _probeDuration(ffmpeg, input.path);

    // Try HEVC first, then H.264 as fallback
    final hevcPath =
        '${outputPath.substring(0, outputPath.lastIndexOf('.'))}_hevc_tmp.mp4';

    final hevcOk = await _runFfmpeg(
      ffmpeg,
      [
        '-i', input.path,
        '-c:v', 'libx265',
        '-preset', 'medium',
        '-crf', '27',
        '-tag:v', 'hvc1',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-movflags', '+faststart',
        hevcPath,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.05,
      progressScale: 0.85,
      onProgress: onProgress,
    );

    if (hevcOk && await File(hevcPath).exists()) {
      final hevcSize = await File(hevcPath).length();
      if (hevcSize < (originalBytes * 0.97).floor()) {
        await File(hevcPath).rename(outputPath);
        onProgress?.call(1.0);
        return CompressionResult(
          outputPath: outputPath,
          originalBytes: originalBytes,
          compressedBytes: hevcSize,
          improved: true,
          note: 'Re-encoded with HEVC/H.265 (CRF 27, preset medium).',
        );
      }
      try {
        await File(hevcPath).delete();
      } catch (_) {}
    }

    // Fallback: H.264
    final h264Ok = await _runFfmpeg(
      ffmpeg,
      [
        '-i', input.path,
        '-c:v', 'libx264',
        '-preset', 'medium',
        '-crf', '23',
        '-tune', 'film',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-movflags', '+faststart',
        outputPath,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.0,
      progressScale: 1.0,
      onProgress: onProgress,
    );

    if (h264Ok && await File(outputPath).exists()) {
      final h264Size = await File(outputPath).length();
      final improved =
          h264Size < originalBytes && (1 - h264Size / originalBytes) > 0.03;
      onProgress?.call(1.0);
      return CompressionResult(
        outputPath: outputPath,
        originalBytes: originalBytes,
        compressedBytes: improved ? h264Size : originalBytes,
        improved: improved,
        note: improved
            ? 'Re-encoded with H.264 (CRF 23, preset medium).'
            : 'Video already optimized; copied as-is.',
      );
    }

    // Last resort: copy original
    await input.copy(outputPath);
    onProgress?.call(1.0);
    return CompressionResult(
      outputPath: outputPath,
      originalBytes: originalBytes,
      compressedBytes: originalBytes,
      improved: false,
      note: 'Compression failed; original copied.',
    );
  }

  /// Reads total duration in seconds from FFmpeg stderr output.
  Future<double> _probeDuration(String ffmpegPath, String inputPath) async {
    try {
      final result = await Process.run(
        ffmpegPath,
        ['-i', inputPath],
        stderrEncoding: utf8,
      );
      final match = RegExp(r'Duration:\s*(\d+):(\d+):([\d.]+)')
          .firstMatch(result.stderr as String);
      if (match != null) {
        final h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final s = double.parse(match.group(3)!);
        return h * 3600 + m * 60 + s;
      }
    } catch (_) {}
    return 0.0;
  }

  Future<bool> _runFfmpeg(
    String ffmpegPath,
    List<String> args, {
    double totalSeconds = 0,
    double progressOffset = 0,
    double progressScale = 1,
    void Function(double)? onProgress,
  }) async {
    final process = await Process.start(ffmpegPath, ['-y', ...args]);

    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
      if (totalSeconds > 0 && onProgress != null) {
        final match =
            RegExp(r'time=(\d+):(\d+):([\d.]+)').firstMatch(chunk);
        if (match != null) {
          final h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          final s = double.parse(match.group(3)!);
          final current = h * 3600 + m * 60 + s;
          final p = (current / totalSeconds).clamp(0.0, 0.99);
          onProgress(progressOffset + progressScale * p);
        }
      }
    });

    process.stdout.drain<void>();
    final exitCode = await process.exitCode;
    return exitCode == 0;
  }
}
