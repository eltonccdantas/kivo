import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import '../utils/cancellation_token.dart';

class JsonService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    final originalBytes = await input.length();
    onProgress?.call(0.1);

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    final raw = await input.readAsString();
    // Strip UTF-8 BOM if present — jsonDecode rejects the \uFEFF character.
    final content = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    onProgress?.call(0.4);

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    final dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (e) {
      throw Exception('Invalid JSON file: $e');
    }

    onProgress?.call(0.7);

    final minified = jsonEncode(parsed);
    await File(outputPath).writeAsString(minified);
    onProgress?.call(1.0);

    final compressedBytes = await File(outputPath).length();
    final improved =
        compressedBytes < originalBytes &&
        (1 - compressedBytes / originalBytes) > 0.001;

    return CompressionResult(
      outputPath: outputPath,
      originalBytes: originalBytes,
      compressedBytes: improved ? compressedBytes : originalBytes,
      improved: improved,
      note: improved
          ? 'Minified: whitespace and formatting removed.'
          : 'JSON already minified; no changes needed.',
    );
  }
}
