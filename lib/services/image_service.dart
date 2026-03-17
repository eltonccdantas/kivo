import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/models.dart';

class ImageService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    int quality = 72, // more aggressive than 82 to ensure real gains
  }) async {
    onProgress?.call(0.1);
    final originalBytes = await input.length();
    final bytes = await input.readAsBytes();

    onProgress?.call(0.25);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image.');

    onProgress?.call(0.5);

    // Re-encoding as JPEG strips all metadata (EXIF, GPS, etc.) and applies
    // fresh quantization — together these provide the most reliable reduction.
    final jpgBytes = img.encodeJpg(decoded, quality: quality);
    onProgress?.call(0.85);

    // Consider improved if output is at least 1% smaller
    final improved =
        jpgBytes.length < originalBytes &&
        (1 - jpgBytes.length / originalBytes) > 0.01;

    // Ensure output has .jpg extension
    final String finalPath;
    final lowerOutput = outputPath.toLowerCase();
    if (lowerOutput.endsWith('.jpg') || lowerOutput.endsWith('.jpeg')) {
      finalPath = outputPath;
    } else {
      final dot = outputPath.lastIndexOf('.');
      finalPath = dot == -1
          ? '$outputPath.jpg'
          : '${outputPath.substring(0, dot)}.jpg';
    }

    if (improved) {
      await File(finalPath).writeAsBytes(jpgBytes, flush: true);
    } else {
      // Still write the file (stripping metadata is valuable even without
      // size reduction), but mark as not improved for UX feedback.
      await File(finalPath).writeAsBytes(jpgBytes, flush: true);
    }

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
