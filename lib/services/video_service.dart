import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../models/models.dart';
import '../utils/binary_extractor.dart';

class VideoService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _compressMobile(input, outputPath, onProgress: onProgress);
    }
    return _compressDesktop(input, outputPath, onProgress: onProgress);
  }

  // ── Mobile (ffmpeg_kit_flutter_full_gpl) ─────────────────────────────────

  Future<CompressionResult> _compressMobile(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
  }) async {
    final originalBytes = await input.length();
    onProgress?.call(0.02);

    // Probe duration for progress reporting
    double totalSeconds = 0;
    try {
      final session = await FFprobeKit.getMediaInformation(input.path);
      final dur = session.getMediaInformation()?.getDuration();
      if (dur != null) totalSeconds = double.tryParse(dur) ?? 0;
    } catch (_) {}

    // Try HEVC first
    final hevcTmp =
        '${outputPath.substring(0, outputPath.lastIndexOf('.'))}_hevc_tmp.mp4';

    final hevcOk = await _runMobileFFmpeg(
      [
        '-y', '-i', input.path,
        '-c:v', 'libx265', '-preset', 'medium', '-crf', '27',
        '-tag:v', 'hvc1',
        '-c:a', 'aac', '-b:a', '128k',
        '-movflags', '+faststart',
        hevcTmp,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.05,
      progressScale: 0.85,
      onProgress: onProgress,
    );

    if (hevcOk && File(hevcTmp).existsSync()) {
      final hevcSize = await File(hevcTmp).length();
      if (hevcSize < (originalBytes * 0.97).floor()) {
        await File(hevcTmp).rename(outputPath);
        onProgress?.call(1.0);
        return CompressionResult(
          outputPath: outputPath,
          originalBytes: originalBytes,
          compressedBytes: hevcSize,
          improved: true,
          note: 'Re-encoded with HEVC/H.265 (CRF 27, preset medium).',
        );
      }
      try { await File(hevcTmp).delete(); } catch (_) {}
    }

    // Fallback: H.264
    final h264Ok = await _runMobileFFmpeg(
      [
        '-y', '-i', input.path,
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '23', '-tune', 'film',
        '-c:a', 'aac', '-b:a', '128k',
        '-movflags', '+faststart',
        outputPath,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.0,
      progressScale: 1.0,
      onProgress: onProgress,
    );

    if (h264Ok && File(outputPath).existsSync()) {
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

  Future<bool> _runMobileFFmpeg(
    List<String> args, {
    double totalSeconds = 0,
    double progressOffset = 0,
    double progressScale = 1,
    void Function(double)? onProgress,
  }) async {
    final completer = Completer<bool>();

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final rc = await session.getReturnCode();
        completer.complete(ReturnCode.isSuccess(rc));
      },
      null,
      totalSeconds > 0 && onProgress != null
          ? (stats) {
              final ms = stats.getTime();
              if (ms > 0) {
                final p = (ms / 1000.0 / totalSeconds).clamp(0.0, 0.99);
                onProgress(progressOffset + progressScale * p);
              }
            }
          : null,
    );

    return completer.future;
  }

  // ── Desktop (Process.start + bundled / system FFmpeg) ────────────────────

  Future<CompressionResult> _compressDesktop(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
  }) async {
    final originalBytes = await input.length();
    onProgress?.call(0.02);

    final ffmpeg = await BinaryExtractor.ffmpegPath();
    final totalSeconds = await _probeDuration(ffmpeg, input.path);

    // Try HEVC first; fall back to H.264 if no meaningful gain
    final hevcTmp =
        '${outputPath.substring(0, outputPath.lastIndexOf('.'))}_hevc_tmp.mp4';

    final hevcOk = await _runFfmpeg(
      ffmpeg,
      [
        '-i', input.path,
        '-c:v', 'libx265', '-preset', 'medium', '-crf', '27',
        '-tag:v', 'hvc1',
        '-c:a', 'aac', '-b:a', '128k',
        '-movflags', '+faststart',
        hevcTmp,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.05,
      progressScale: 0.85,
      onProgress: onProgress,
    );

    if (hevcOk && await File(hevcTmp).exists()) {
      final hevcSize = await File(hevcTmp).length();
      if (hevcSize < (originalBytes * 0.97).floor()) {
        await File(hevcTmp).rename(outputPath);
        onProgress?.call(1.0);
        return CompressionResult(
          outputPath: outputPath,
          originalBytes: originalBytes,
          compressedBytes: hevcSize,
          improved: true,
          note: 'Re-encoded with HEVC/H.265 (CRF 27, preset medium).',
        );
      }
      try { await File(hevcTmp).delete(); } catch (_) {}
    }

    // Fallback: H.264
    await _runFfmpeg(
      ffmpeg,
      [
        '-i', input.path,
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '23', '-tune', 'film',
        '-c:a', 'aac', '-b:a', '128k',
        '-movflags', '+faststart',
        outputPath,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.0,
      progressScale: 1.0,
      onProgress: onProgress,
    );

    if (await File(outputPath).exists()) {
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
    return await process.exitCode == 0;
  }
}
