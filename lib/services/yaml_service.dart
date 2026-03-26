import 'dart:io';

import '../models/models.dart';
import '../utils/cancellation_token.dart';

class YamlService {
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

    final lines = await input.readAsLines();
    onProgress?.call(0.5);

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    final minified = lines
        .map((line) {
          // Remove inline comments, but only outside quoted strings.
          // Strategy: strip trailing " #..." only when preceded by whitespace,
          // to avoid breaking values like "http://example.com" or "key: '#value'".
          final stripped = _stripInlineComment(line);
          return stripped.trimRight();
        })
        .where((line) => line.isNotEmpty) // drop blank lines
        .join('\n');

    if (minified.isEmpty) {
      throw Exception('YAML file is empty after minification.');
    }

    await File(outputPath).writeAsString('$minified\n');
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
          ? 'Minified: comments and blank lines removed.'
          : 'YAML already minified; no changes needed.',
    );
  }

  /// Removes a trailing `# comment` from a line, respecting single and double
  /// quoted strings so URLs and hash values are not accidentally trimmed.
  String _stripInlineComment(String line) {
    // Full-line comment — drop the entire line content (becomes blank → filtered).
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) return '';

    // Walk the line character by character to find an unquoted " #".
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (ch == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (ch == '#' && !inSingle && !inDouble) {
        // Only strip if preceded by whitespace (YAML spec requirement).
        if (i > 0 && (line[i - 1] == ' ' || line[i - 1] == '\t')) {
          return line.substring(0, i);
        }
      }
    }
    return line;
  }
}
