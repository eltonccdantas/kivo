class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class CompressionCancelledException implements Exception {
  const CompressionCancelledException();
}
