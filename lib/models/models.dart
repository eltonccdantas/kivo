import 'dart:io';

enum FileKind { image, video, pdf, unsupported }

enum QueueStatus { waiting, compressing, done, error, cancelled }

class QueueItem {
  final String id;
  final File file;
  final FileKind kind;
  QueueStatus status;
  CompressionResult? result;
  String? errorMessage;
  double progress;
  String statusMessage;

  QueueItem({required this.file, required this.kind})
      : id = '${file.path}_${DateTime.now().microsecondsSinceEpoch}',
        status = QueueStatus.waiting,
        progress = 0.0,
        statusMessage = '';
}

class CompressionResult {
  final String outputPath;
  final int originalBytes;
  final int compressedBytes;
  final bool improved;
  final String note;

  const CompressionResult({
    required this.outputPath,
    required this.originalBytes,
    required this.compressedBytes,
    required this.improved,
    required this.note,
  });

  double get reductionPercent {
    if (originalBytes == 0) return 0.0;
    return (1 - compressedBytes / originalBytes.toDouble()).clamp(0.0, 1.0) * 100;
  }
}
