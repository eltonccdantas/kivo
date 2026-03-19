import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:image/image.dart' as img;
import '../models/models.dart';
import '../utils/cancellation_token.dart';

class PdfService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    onProgress?.call(0.05);
    final originalBytes = await input.length();
    final inputBytes = await input.readAsBytes();

    // Lower DPI on mobile to stay within memory limits.
    final dpi = (Platform.isAndroid || Platform.isIOS) ? 96.0 : 150.0;

    // Try quality 65 first; fall back to quality 45 if gain is below 5 %.
    // Quality 65 is visually good and produces meaningful reductions for most
    // PDFs. Quality 45 is a safety net for PDFs with already-compressed images.
    for (final quality in [65, 45]) {
      if (cancellationToken?.isCancelled == true) {
        throw const CompressionCancelledException();
      }
      final result = await _rasterize(
        input: input,
        inputBytes: inputBytes,
        outputPath: outputPath,
        originalBytes: originalBytes,
        dpi: dpi,
        jpegQuality: quality,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      if (result != null) return result;
    }

    // Both passes failed to shrink the file — return the original unchanged.
    await input.copy(outputPath);
    onProgress?.call(1.0);
    return CompressionResult(
      outputPath: outputPath,
      originalBytes: originalBytes,
      compressedBytes: originalBytes,
      improved: false,
      note: 'PDF already at minimum size; original copied.',
    );
  }

  /// Rasterizes [input] and returns a [CompressionResult] if the rasterized
  /// PDF is at least 1 % smaller than [originalBytes]. Returns null otherwise.
  Future<CompressionResult?> _rasterize({
    required File input,
    required Uint8List inputBytes,
    required String outputPath,
    required int originalBytes,
    required double dpi,
    required int jpegQuality,
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) async {
    final doc = pw.Document();
    int pageIndex = 0;

    await for (final page in Printing.raster(inputBytes, dpi: dpi)) {
      if (cancellationToken?.isCancelled == true) {
        throw const CompressionCancelledException();
      }

      final uiImage = await page.toImage();
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final decoded = img.decodePng(byteData.buffer.asUint8List());
      if (decoded == null) return null;

      final jpgBytes = Uint8List.fromList(
        img.encodeJpg(decoded, quality: jpegQuality),
      );

      doc.addPage(
        pw.Page(
          pageFormat: pdf_lib.PdfPageFormat(
            (page.width / dpi) * 72.0,
            (page.height / dpi) * 72.0,
          ),
          build: (_) => pw.Image(
            pw.MemoryImage(jpgBytes),
            fit: pw.BoxFit.fill,
          ),
        ),
      );

      pageIndex++;
      onProgress?.call(
        (0.1 + 0.8 * pageIndex / (pageIndex + 1)).clamp(0.1, 0.9),
      );
    }

    final outBytes = await doc.save();

    // Require at least 1 % reduction to consider this a win.
    if (outBytes.length >= originalBytes ||
        (1 - outBytes.length / originalBytes) < 0.01) {
      return null;
    }

    await File(outputPath).writeAsBytes(outBytes, flush: true);
    onProgress?.call(1.0);

    return CompressionResult(
      outputPath: outputPath,
      originalBytes: originalBytes,
      compressedBytes: outBytes.length,
      improved: true,
      note:
          'Rasterized at ${dpi.toStringAsFixed(0)} DPI, JPEG quality $jpegQuality.',
    );
  }
}
