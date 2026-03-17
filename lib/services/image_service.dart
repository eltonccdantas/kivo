import 'dart:io';
import 'package:image/image.dart' as img;
import '../models/models.dart';

class ImageService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    int quality = 82,
  }) async {
    onProgress?.call(0.1);
    final originalBytes = await input.length();
    final bytes = await input.readAsBytes();

    onProgress?.call(0.25);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image.');

    onProgress?.call(0.5);
    final jpgBytes = img.encodeJpg(decoded, quality: quality);
    onProgress?.call(0.85);

    final improved =
        jpgBytes.length < originalBytes &&
        (1 - jpgBytes.length / originalBytes) > 0.03;

    // Ensure output has .jpg extension
    final finalPath = outputPath.toLowerCase().endsWith('.jpg') ||
            outputPath.toLowerCase().endsWith('.jpeg')
        ? outputPath
        : '${outputPath.substring(0, outputPath.lastIndexOf('.'))}.jpg';

    if (improved) {
      await File(finalPath).writeAsBytes(jpgBytes, flush: true);
    } else {
      await input.copy(finalPath);
    }

    onProgress?.call(1.0);

    return CompressionResult(
      outputPath: finalPath,
      originalBytes: originalBytes,
      compressedBytes: improved ? jpgBytes.length : originalBytes,
      improved: improved,
      note: improved
          ? 'Compressed to JPEG (quality=$quality).'
          : 'Already optimized; file copied as-is.',
    );
  }
}
