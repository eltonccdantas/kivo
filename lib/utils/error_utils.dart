/// Maps a raw compression exception to a short, user-friendly message.
///
/// Callers should log the original exception separately (e.g. via debugPrint)
/// before calling this function so the technical detail is not lost.
String friendlyCompressionError(Object e) {
  final msg = e.toString();

  if (msg.contains('Video encoding failed') ||
      msg.contains('Error submitting video frame') ||
      msg.contains('Conversion failed') ||
      msg.contains('mediacodec') ||
      msg.contains('videotoolbox')) {
    return 'Video compression failed. Your device may not support this format or codec.';
  }

  if (msg.contains('FFmpeg not found') || msg.contains('ProcessException')) {
    return 'FFmpeg is not available. Please install it (e.g. brew install ffmpeg).';
  }

  if (msg.contains('PathNotFoundException') ||
      msg.contains('No such file or directory')) {
    return 'File not found. It may have been moved or deleted.';
  }

  if (msg.contains('out of memory') || msg.contains('OutOfMemory')) {
    return 'Not enough memory to compress this file. Try a smaller file.';
  }

  if (msg.contains('cancelled') || msg.contains('Cancelled')) {
    return 'Compression was cancelled.';
  }

  return 'Compression failed. Please try again.';
}
