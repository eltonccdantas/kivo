import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:image/image.dart' as img;
import '../models/models.dart';

class PdfService {
  Future<CompressionResult> compress(
    File input,
    String outputPath, {
    void Function(double)? onProgress,
    double dpi = 150.0,
    int jpegQuality = 80,
  }) async {
    onProgress?.call(0.05);
    final originalBytes = await input.length();
    final inputBytes = await input.readAsBytes();

    // Rasterize pages
    final rasters = Printing.raster(inputBytes, dpi: dpi);
    final doc = pw.Document();

    // Count pages first for accurate progress
    final pages = await rasters.toList();
    final total = pages.length;

    for (int i = 0; i < total; i++) {
      final page = pages[i];
      final uiImage = await page.toImage();
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to rasterize page ${i + 1}.');

      final pngBytes = byteData.buffer.asUint8List();
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) throw Exception('Failed to decode page ${i + 1}.');

      final jpgBytes = Uint8List.fromList(
        img.encodeJpg(decoded, quality: jpegQuality),
      );

      final pageFormat = pdf_lib.PdfPageFormat(
        (page.width / dpi) * 72.0,
        (page.height / dpi) * 72.0,
      );

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (_) => pw.Image(
            pw.MemoryImage(jpgBytes),
            fit: pw.BoxFit.fill,
          ),
        ),
      );

      onProgress?.call(0.1 + 0.8 * ((i + 1) / total));
    }

    final outBytes = await doc.save();
    await File(outputPath).writeAsBytes(outBytes, flush: true);
    onProgress?.call(1.0);

    final improved =
        outBytes.length < originalBytes &&
        (1 - outBytes.length / originalBytes) > 0.03;

    return CompressionResult(
      outputPath: outputPath,
      originalBytes: originalBytes,
      compressedBytes: outBytes.length,
      improved: improved,
      note: improved
          ? 'Rasterized at ${dpi.toStringAsFixed(0)} DPI, re-encoded as JPEG (quality=$jpegQuality).'
          : 'PDF already optimized; output may be similar size.',
    );
  }
}
