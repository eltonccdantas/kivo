import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import '../models/models.dart';
import '../utils/cancellation_token.dart';

class ImageService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    int quality = 72,
    CancellationToken? cancellationToken,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _compressMobile(input, outputPath,
          onProgress: onProgress,
          quality: quality,
          cancellationToken: cancellationToken);
    }
    return _compressDesktop(input, outputPath,
        onProgress: onProgress,
        quality: quality,
        cancellationToken: cancellationToken);
  }

  // ── Mobile ────────────────────────────────────────────────────────────────
  // Uses flutter_image_compress which decodes via platform APIs
  // (BitmapFactory on Android, UIImage on iOS) — supports HEIC/HEIF natively.

  Future<CompressionResult> _compressMobile(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    int quality = 72,
    CancellationToken? cancellationToken,
  }) async {
    onProgress?.call(0.1);
    final originalBytes = await input.length();

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    // Output must be JPEG (flutter_image_compress always encodes to JPEG).
    final String finalPath;
    final lowerOutput = outputPath.toLowerCase();
    if (lowerOutput.endsWith('.jpg') || lowerOutput.endsWith('.jpeg')) {
      finalPath = outputPath;
    } else {
      final dot = outputPath.lastIndexOf('.');
      finalPath =
          dot == -1 ? '$outputPath.jpg' : '${outputPath.substring(0, dot)}.jpg';
    }

    onProgress?.call(0.3);

    final compressed = await FlutterImageCompress.compressWithFile(
      input.absolute.path,
      quality: quality,
    );

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    if (compressed == null) throw Exception('Could not decode image.');

    onProgress?.call(0.85);

    final improved = compressed.length < originalBytes &&
        (1 - compressed.length / originalBytes) > 0.01;

    await File(finalPath).writeAsBytes(compressed, flush: true);
    onProgress?.call(1.0);

    return CompressionResult(
      outputPath: finalPath,
      originalBytes: originalBytes,
      compressedBytes: compressed.length,
      improved: improved,
      note: improved
          ? 'Compressed to JPEG (quality=$quality, metadata stripped).'
          : 'Image already well-compressed; saved with metadata stripped.',
    );
  }

  // ── Desktop ───────────────────────────────────────────────────────────────
  // Uses the pure-Dart `image` package (no platform plugins needed).

  Future<CompressionResult> _compressDesktop(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    int quality = 72,
    CancellationToken? cancellationToken,
  }) async {
    onProgress?.call(0.1);
    final originalBytes = await input.length();
    final bytes = await input.readAsBytes();

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    onProgress?.call(0.25);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image.');

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    onProgress?.call(0.5);
    final jpgBytes = img.encodeJpg(decoded, quality: quality);
    onProgress?.call(0.85);

    final improved = jpgBytes.length < originalBytes &&
        (1 - jpgBytes.length / originalBytes) > 0.01;

    final String finalPath;
    final lowerOutput = outputPath.toLowerCase();
    if (lowerOutput.endsWith('.jpg') || lowerOutput.endsWith('.jpeg')) {
      finalPath = outputPath;
    } else {
      final dot = outputPath.lastIndexOf('.');
      finalPath =
          dot == -1 ? '$outputPath.jpg' : '${outputPath.substring(0, dot)}.jpg';
    }

    await File(finalPath).writeAsBytes(jpgBytes, flush: true);
    onProgress?.call(1.0);

    return CompressionResult(
      outputPath: finalPath,
      originalBytes: originalBytes,
      compressedBytes: jpgBytes.length,
      improved: improved,
      note: improved
          ? 'Compressed to JPEG (quality=$quality, metadata stripped).'
          : 'Image already well-compressed; saved with metadata stripped.',
    );
  }
}
