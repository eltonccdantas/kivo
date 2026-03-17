enum FileKind { image, video, pdf, unsupported }

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

  double get reductionPercent =>
      (1 - compressedBytes / originalBytes.toDouble()).clamp(0.0, 1.0) * 100;
}
