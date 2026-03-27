import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/utils/error_utils.dart';

void main() {
  group('friendlyCompressionError — video codec errors', () {
    test('matches "Video encoding failed"', () {
      expect(
        friendlyCompressionError(Exception('Video encoding failed.')),
        contains('Video compression failed'),
      );
    });

    test('matches "Error submitting video frame"', () {
      expect(
        friendlyCompressionError(
            Exception('Error submitting video frame to the encoder')),
        contains('Video compression failed'),
      );
    });

    test('matches "Conversion failed"', () {
      expect(
        friendlyCompressionError(Exception('Conversion failed!')),
        contains('Video compression failed'),
      );
    });

    test('matches "mediacodec" (Android hardware encoder)', () {
      expect(
        friendlyCompressionError(
            Exception('[h264_mediacodec] Use 1 as the default')),
        contains('Video compression failed'),
      );
    });

    test('matches "videotoolbox" (iOS hardware encoder)', () {
      expect(
        friendlyCompressionError(
            Exception('hevc_videotoolbox encoder not available')),
        contains('Video compression failed'),
      );
    });

    test('video error message mentions codec support', () {
      final msg =
          friendlyCompressionError(Exception('Video encoding failed.'));
      expect(msg, contains('codec'));
    });
  });

  group('friendlyCompressionError — FFmpeg not found', () {
    test('matches "FFmpeg not found"', () {
      expect(
        friendlyCompressionError(Exception('FFmpeg not found or could not be started.')),
        contains('FFmpeg is not available'),
      );
    });

    test('matches "ProcessException"', () {
      expect(
        friendlyCompressionError(Exception('ProcessException: ...')),
        contains('FFmpeg is not available'),
      );
    });

    test('FFmpeg message mentions brew install', () {
      final msg =
          friendlyCompressionError(Exception('FFmpeg not found.'));
      expect(msg, contains('brew install ffmpeg'));
    });
  });

  group('friendlyCompressionError — file not found', () {
    test('matches "PathNotFoundException"', () {
      expect(
        friendlyCompressionError(
            Exception('PathNotFoundException: No such file')),
        contains('File not found'),
      );
    });

    test('matches "No such file or directory"', () {
      expect(
        friendlyCompressionError(
            Exception('OS Error: No such file or directory, errno = 2')),
        contains('File not found'),
      );
    });

    test('file not found message mentions moved or deleted', () {
      final msg = friendlyCompressionError(
          Exception('PathNotFoundException: ...'));
      expect(msg, contains('moved or deleted'));
    });
  });

  group('friendlyCompressionError — out of memory', () {
    test('matches "out of memory"', () {
      expect(
        friendlyCompressionError(Exception('out of memory')),
        contains('Not enough memory'),
      );
    });

    test('matches "OutOfMemory"', () {
      expect(
        friendlyCompressionError(Exception('java.lang.OutOfMemoryError')),
        contains('Not enough memory'),
      );
    });

    test('OOM message mentions smaller file', () {
      final msg = friendlyCompressionError(Exception('out of memory'));
      expect(msg, contains('smaller file'));
    });
  });

  group('friendlyCompressionError — cancelled', () {
    test('matches lowercase "cancelled"', () {
      expect(
        friendlyCompressionError(Exception('operation cancelled by user')),
        contains('cancelled'),
      );
    });

    test('matches capitalized "Cancelled"', () {
      expect(
        friendlyCompressionError(Exception('Cancelled')),
        contains('cancelled'),
      );
    });
  });

  group('friendlyCompressionError — unknown / generic errors', () {
    test('unknown exception returns generic message', () {
      expect(
        friendlyCompressionError(Exception('some unexpected error')),
        'Compression failed. Please try again.',
      );
    });

    test('empty message returns generic message', () {
      expect(
        friendlyCompressionError(Exception('')),
        'Compression failed. Please try again.',
      );
    });

    test('StateError returns generic message', () {
      expect(
        friendlyCompressionError(StateError('bad state')),
        'Compression failed. Please try again.',
      );
    });

    test('generic message asks user to try again', () {
      final msg = friendlyCompressionError(Exception('???'));
      expect(msg, contains('try again'));
    });
  });

  group('friendlyCompressionError — pattern priority', () {
    test('video error takes priority over generic patterns', () {
      // Contains both a video keyword and an unrelated word — video wins.
      final msg = friendlyCompressionError(
          Exception('Video encoding failed: unexpected error xyz'));
      expect(msg, contains('Video compression failed'));
      expect(msg, isNot('Compression failed. Please try again.'));
    });

    test('different exception types return a message', () {
      expect(friendlyCompressionError(FormatException('bad format')),
          isNotEmpty);
      expect(friendlyCompressionError(ArgumentError('bad arg')), isNotEmpty);
      expect(friendlyCompressionError(RangeError('out of range')), isNotEmpty);
    });
  });

  group('friendlyCompressionError — message is always non-empty', () {
    final cases = [
      Exception('Video encoding failed.'),
      Exception('FFmpeg not found.'),
      Exception('PathNotFoundException'),
      Exception('out of memory'),
      Exception('Cancelled'),
      Exception('totally unknown error'),
      Exception(''),
    ];

    for (final e in cases) {
      test('non-empty for: ${e.toString()}', () {
        expect(friendlyCompressionError(e).trim(), isNotEmpty);
      });
    }
  });
}
