import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../utils/binary_extractor.dart';
import '../utils/cancellation_token.dart';

class VideoService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _compressMobile(input, outputPath,
          onProgress: onProgress, cancellationToken: cancellationToken);
    }
    return _compressDesktop(input, outputPath,
        onProgress: onProgress, cancellationToken: cancellationToken);
  }

  // ── Mobile (ffmpeg_kit_flutter_new) ──────────────────────────────────────

  Future<CompressionResult> _compressMobile(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    final originalBytes = await input.length();
    onProgress?.call(0.02);

    double totalSeconds = 0;
    try {
      final session = await FFprobeKit.getMediaInformation(input.path);
      final dur = session.getMediaInformation()?.getDuration();
      if (dur != null) totalSeconds = double.tryParse(dur) ?? 0;
    } catch (_) {}

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    // ffmpeg_kit_flutter_new ships the full-gpl build, so libx264/libx265 ARE
    // available on both Android and iOS. Hardware encoders are still preferred
    // because they are 10-20× faster on device, but libx264 is used as the
    // final fallback because it handles any input pixel format (including GBR).
    final isAndroid = Platform.isAndroid;

    // For hardware encoding we need a target bitrate.
    // Aim for ~60 % of the estimated original bitrate; clamp to a safe range.
    final targetKbps = isAndroid
        ? totalSeconds > 0
            ? ((originalBytes * 8 / totalSeconds / 1000) * 0.6)
                .clamp(400.0, 8000.0)
                .round()
            : 2000
        : 0; // unused on iOS — CRF controls quality there

    final hevcTmp =
        '${outputPath.substring(0, outputPath.lastIndexOf('.'))}_hevc_tmp.mp4';

    // Attempt 1 — HEVC hardware encoder.
    // Android: nv12 = COLOR_FormatYUV420SemiPlanar, the native MediaCodec
    // pixel format. Using yuv420p causes BAD_VALUE at configure time on many
    // devices ("Please try -pix_fmt nv12" in FFmpeg's own error message).
    // iOS: VideoToolbox accepts yuv420p directly.
    final hevcArgs = isAndroid
        ? [
            '-y',
            '-i',
            input.path,
            '-c:v',
            'hevc_mediacodec',
            '-b:v',
            '${targetKbps}k',
            '-pix_fmt',
            'nv12',
            '-c:a',
            'aac',
            '-b:a',
            '128k',
            hevcTmp,
          ]
        : [
            '-y',
            '-i',
            input.path,
            '-c:v',
            'hevc_videotoolbox',
            '-b:v',
            '${targetKbps}k',
            '-tag:v',
            'hvc1',
            '-pix_fmt',
            'yuv420p',
            '-c:a',
            'aac',
            '-b:a',
            '128k',
            '-movflags',
            '+faststart',
            hevcTmp,
          ];

    final (hevcOk, hevcError) = await _runMobileFFmpeg(
      hevcArgs,
      totalSeconds: totalSeconds,
      progressOffset: 0.05,
      progressScale: 0.80,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );

    if (cancellationToken?.isCancelled == true) {
      try {
        await File(hevcTmp).delete();
      } catch (_) {}
      throw const CompressionCancelledException();
    }

    if (hevcOk && File(hevcTmp).existsSync()) {
      final hevcSize = await File(hevcTmp).length();
      // Guard: some hardware encoders return exit-code 0 but write a near-empty
      // corrupt file when the source colorspace (e.g. GBR) is unsupported.
      final minViable =
          (originalBytes * 0.005).floor().clamp(50 * 1024, 1 << 30);
      if (hevcSize >= minViable && hevcSize < (originalBytes * 0.97).floor()) {
        await File(hevcTmp).rename(outputPath);
        onProgress?.call(1.0);
        return CompressionResult(
          outputPath: outputPath,
          originalBytes: originalBytes,
          compressedBytes: hevcSize,
          improved: true,
          note: isAndroid
              ? 'Re-encoded with HEVC (MediaCodec, $targetKbps kbps).'
              : 'Re-encoded with HEVC (VideoToolbox, $targetKbps kbps).',
        );
      }
      try {
        await File(hevcTmp).delete();
      } catch (_) {}
    }

    // Attempt 2 — H.264 hardware encoder, same nv12 reasoning as above.
    final h264Args = isAndroid
        ? [
            '-y',
            '-i',
            input.path,
            '-c:v',
            'h264_mediacodec',
            '-b:v',
            '${targetKbps}k',
            '-pix_fmt',
            'nv12',
            '-c:a',
            'aac',
            '-b:a',
            '128k',
            outputPath,
          ]
        : [
            '-y',
            '-i',
            input.path,
            '-c:v',
            'h264_videotoolbox',
            '-b:v',
            '${targetKbps}k',
            '-pix_fmt',
            'yuv420p',
            '-c:a',
            'aac',
            '-b:a',
            '128k',
            '-movflags',
            '+faststart',
            outputPath,
          ];

    final (h264Ok, h264Error) = await _runMobileFFmpeg(
      h264Args,
      totalSeconds: totalSeconds,
      progressOffset: 0.0,
      progressScale: 0.65,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    if (h264Ok && File(outputPath).existsSync()) {
      final h264Size = await File(outputPath).length();
      final minViable =
          (originalBytes * 0.005).floor().clamp(50 * 1024, 1 << 30);
      if (h264Size >= minViable) {
        final improved =
            h264Size < originalBytes && (1 - h264Size / originalBytes) > 0.03;
        onProgress?.call(1.0);
        return CompressionResult(
          outputPath: outputPath,
          originalBytes: originalBytes,
          compressedBytes: improved ? h264Size : originalBytes,
          improved: improved,
          note: improved
              ? isAndroid
                  ? 'Re-encoded with H.264 (MediaCodec, $targetKbps kbps).'
                  : 'Re-encoded with H.264 (VideoToolbox, $targetKbps kbps).'
              : 'Video already optimized; copied as-is.',
        );
      }
      try {
        await File(outputPath).delete();
      } catch (_) {}
    }

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    // Attempt 3 — libx264 software encoder (full-gpl build bundles it).
    // Hardware encoders failed: either the device rejects the pixel format or
    // the source has an unusual colorspace (e.g. GBR from ProRes .mov files).
    // libx264 is a pure-software encoder: it accepts any decoded frame format
    // and libswscale handles the colorspace conversion correctly, so this works
    // for GBR/ProRes inputs where the hardware path silently produces corrupt
    // near-empty output.  It is slower (~10× vs hardware) but always correct.
    final x264Args = [
      '-y',
      '-i',
      input.path,
      '-vf',
      'format=yuv420p', // explicit software conversion handles GBR → YUV420P
      '-c:v',
      'libx264',
      '-crf',
      '23',
      '-preset',
      'fast',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
      outputPath,
    ];

    final (x264Ok, x264Error) = await _runMobileFFmpeg(
      x264Args,
      totalSeconds: totalSeconds,
      progressOffset: 0.0,
      progressScale: 1.0,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    if (x264Ok && File(outputPath).existsSync()) {
      final x264Size = await File(outputPath).length();
      final minViable =
          (originalBytes * 0.005).floor().clamp(50 * 1024, 1 << 30);
      if (x264Size >= minViable) {
        final improved =
            x264Size < originalBytes && (1 - x264Size / originalBytes) > 0.03;
        onProgress?.call(1.0);
        return CompressionResult(
          outputPath: outputPath,
          originalBytes: originalBytes,
          compressedBytes: improved ? x264Size : originalBytes,
          improved: improved,
          note: improved
              ? 'Re-encoded with H.264 (libx264, CRF 23).'
              : 'Video already optimized; copied as-is.',
        );
      }
      try {
        await File(outputPath).delete();
      } catch (_) {}
    }

    // All three attempts failed.
    final errorDetail =
        x264Error ?? h264Error ?? hevcError ?? 'No details available.';
    throw Exception('Video encoding failed.\n\n$errorDetail');
  }

  // Returns (success, errorLog). errorLog is non-null only on failure and
  // contains the last few hundred chars of the FFmpeg output, useful for
  // surfacing the real reason compression failed (e.g. "Encoder not found").
  Future<(bool, String?)> _runMobileFFmpeg(
    List<String> args, {
    double totalSeconds = 0,
    double progressOffset = 0,
    double progressScale = 1,
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    final completer = Completer<(bool, String?)>();

    try {
      await FFmpegKit.executeWithArgumentsAsync(
        args,
        (session) async {
          final rc = await session.getReturnCode();
          final success = ReturnCode.isSuccess(rc);
          if (success) {
            completer.complete((true, null));
          } else {
            // Capture the tail of the log so callers can surface the error.
            final raw = await session.getAllLogsAsString();
            final tail = raw != null && raw.length > 600
                ? raw.substring(raw.length - 600)
                : raw;
            completer.complete((false, tail));
          }
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
    } on MissingPluginException {
      completer.complete((false, 'FFmpegKit plugin not available.'));
      return completer.future;
    }

    // Wire up cancellation: poll until the session finishes or is cancelled.
    if (cancellationToken != null) {
      Future.doWhile(() async {
        if (completer.isCompleted) return false;
        if (cancellationToken.isCancelled) {
          try {
            await FFmpegKit.cancel();
          } catch (_) {}
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return true;
      }).catchError((_) {});
    }

    return completer.future;
  }

  // ── Desktop (Process.start + bundled / system FFmpeg) ────────────────────

  Future<CompressionResult> _compressDesktop(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    final originalBytes = await input.length();
    onProgress?.call(0.02);

    final ffmpeg = await BinaryExtractor.ffmpegPath();
    final totalSeconds = await _probeDuration(ffmpeg, input.path);

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    // Try HEVC first; fall back to H.264 if no meaningful gain
    final hevcTmp =
        '${outputPath.substring(0, outputPath.lastIndexOf('.'))}_hevc_tmp.mp4';

    final hevcOk = await _runFfmpeg(
      ffmpeg,
      [
        '-i',
        input.path,
        '-c:v',
        'libx265',
        '-preset',
        'medium',
        '-crf',
        '27',
        '-tag:v',
        'hvc1',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
        hevcTmp,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.05,
      progressScale: 0.85,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );

    if (cancellationToken?.isCancelled == true) {
      try {
        await File(hevcTmp).delete();
      } catch (_) {}
      throw const CompressionCancelledException();
    }

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
      try {
        await File(hevcTmp).delete();
      } catch (_) {}
    }

    // Fallback: H.264
    await _runFfmpeg(
      ffmpeg,
      [
        '-i',
        input.path,
        '-c:v',
        'libx264',
        '-preset',
        'medium',
        '-crf',
        '23',
        '-tune',
        'film',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
        outputPath,
      ],
      totalSeconds: totalSeconds,
      progressOffset: 0.0,
      progressScale: 1.0,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

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
    CancellationToken? cancellationToken,
  }) async {
    final Process process;
    try {
      process = await Process.start(ffmpegPath, ['-y', ...args]);
    } on ProcessException catch (e) {
      throw Exception(
        'FFmpeg not found or could not be started.\n'
        'Make sure FFmpeg is installed (brew install ffmpeg on macOS).\n'
        'Details: $e',
      );
    }

    // Drain stdout immediately so FFmpeg never blocks on a full pipe buffer.
    // Errors are swallowed — stdout is unused.
    process.stdout.drain<void>().catchError((_) {});

    // stderr carries FFmpeg progress info; swallow stream errors so a
    // broken pipe or early process exit doesn't produce an unhandled exception.
    process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(
      (chunk) {
        if (totalSeconds > 0 && onProgress != null) {
          final match = RegExp(r'time=(\d+):(\d+):([\d.]+)').firstMatch(chunk);
          if (match != null) {
            final h = int.parse(match.group(1)!);
            final m = int.parse(match.group(2)!);
            final s = double.parse(match.group(3)!);
            final current = h * 3600 + m * 60 + s;
            final p = (current / totalSeconds).clamp(0.0, 0.99);
            onProgress(progressOffset + progressScale * p);
          }
        }
      },
      onError: (_) {}, // ignore stream-level errors (e.g. broken pipe)
    );

    // Kill the process if cancelled while it's running.
    // The loop checks a shared flag so it stops as soon as exitCode resolves,
    // preventing the doWhile from running forever after the process exits.
    var processRunning = true;
    if (cancellationToken != null) {
      Future.doWhile(() async {
        if (!processRunning) return false;
        if (cancellationToken.isCancelled) {
          try {
            process.kill();
          } catch (_) {}
          return false;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return processRunning;
      }).catchError((_) {});
    }

    final exitCode = await process.exitCode;
    processRunning = false;
    return exitCode == 0;
  }
}
