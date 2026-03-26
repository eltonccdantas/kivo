import 'dart:io';

import 'package:xml/xml.dart';

import '../models/models.dart';
import '../utils/cancellation_token.dart';

class XmlService {
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
    // Strip UTF-8 BOM — the xml parser rejects a leading \uFEFF before <?xml.
    final content = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    onProgress?.call(0.4);

    if (cancellationToken?.isCancelled == true) {
      throw const CompressionCancelledException();
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(content);
    } catch (e) {
      throw Exception('Invalid XML file: $e');
    }

    onProgress?.call(0.7);

    _stripWhitespaceNodes(document);
    final minified = document.toXmlString(pretty: false);
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
          : 'XML already minified; no changes needed.',
    );
  }

  /// Removes whitespace-only text nodes so that pretty-printed XML
  /// is genuinely compacted when re-serialised with pretty: false.
  void _stripWhitespaceNodes(XmlNode node) {
    final whitespace = node.children
        .where((c) => c is XmlText && c.value.trim().isEmpty)
        .toList();
    for (final ws in whitespace) {
      ws.remove();
    }
    for (final child in node.children.toList()) {
      _stripWhitespaceNodes(child);
    }
  }
}
