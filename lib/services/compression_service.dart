import 'dart:io';
import '../models/models.dart';
import '../utils/cancellation_token.dart';
import 'image_service.dart';
import 'json_service.dart';
import 'pdf_service.dart';
import 'xml_service.dart';
import 'yaml_service.dart';
import 'video_service.dart';

class CompressionService {
  final _imageService = ImageService();
  final _jsonService = JsonService();
  final _pdfService = PdfService();
  final _videoService = VideoService();
  final _xmlService = XmlService();
  final _yamlService = YamlService();

  Future<CompressionResult> compress(
    File input,
    FileKind kind,
    String outputPath, {
    void Function(double)? onProgress,
    CancellationToken? cancellationToken,
  }) {
    switch (kind) {
      case FileKind.image:
        return _imageService.compress(
          input,
          outputPath,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      case FileKind.video:
        return _videoService.compress(
          input,
          outputPath,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      case FileKind.pdf:
        return _pdfService.compress(
          input,
          outputPath,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      case FileKind.json:
        return _jsonService.compress(
          input,
          outputPath,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      case FileKind.xml:
        return _xmlService.compress(
          input,
          outputPath,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      case FileKind.yaml:
        return _yamlService.compress(
          input,
          outputPath,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
      case FileKind.unsupported:
        throw Exception('Unsupported file type.');
    }
  }
}
