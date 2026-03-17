import 'dart:io';
import '../models/models.dart';
import 'image_service.dart';
import 'pdf_service.dart';
import 'video_service.dart';

class CompressionService {
  final _imageService = ImageService();
  final _pdfService = PdfService();
  final _videoService = VideoService();

  Future<CompressionResult> compress(
    File input,
    FileKind kind,
    String outputPath, {
    void Function(double)? onProgress,
  }) {
    switch (kind) {
      case FileKind.image:
        return _imageService.compress(
          input,
          outputPath,
          onProgress: onProgress,
        );
      case FileKind.video:
        return _videoService.compress(
          input,
          outputPath,
          onProgress: onProgress,
        );
      case FileKind.pdf:
        return _pdfService.compress(
          input,
          outputPath,
          onProgress: onProgress,
        );
      case FileKind.unsupported:
        throw Exception('Unsupported file type.');
    }
  }
}
