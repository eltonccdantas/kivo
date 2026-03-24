import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/models/models.dart';

void main() {
  group('QueueStatus', () {
    test('has exactly 5 values', () {
      expect(QueueStatus.values.length, 5);
    });

    test('contains all expected members', () {
      expect(
        QueueStatus.values,
        containsAll([
          QueueStatus.waiting,
          QueueStatus.compressing,
          QueueStatus.done,
          QueueStatus.error,
          QueueStatus.cancelled,
        ]),
      );
    });

    test('all values are distinct', () {
      final values = QueueStatus.values;
      expect(values.toSet().length, values.length);
    });
  });

  group('QueueItem — initial state', () {
    late QueueItem item;

    setUp(() {
      item = QueueItem(
        file: File('/tmp/video.mp4'),
        kind: FileKind.video,
      );
    });

    test('starts with waiting status', () {
      expect(item.status, QueueStatus.waiting);
    });

    test('starts with zero progress', () {
      expect(item.progress, 0.0);
    });

    test('starts with empty statusMessage', () {
      expect(item.statusMessage, '');
    });

    test('starts with no result', () {
      expect(item.result, isNull);
    });

    test('starts with no errorMessage', () {
      expect(item.errorMessage, isNull);
    });

    test('stores file correctly', () {
      expect(item.file.path, '/tmp/video.mp4');
    });

    test('stores kind correctly', () {
      expect(item.kind, FileKind.video);
    });
  });

  group('QueueItem — ID generation', () {
    test('ID is non-empty', () {
      final item = QueueItem(file: File('/tmp/a.jpg'), kind: FileKind.image);
      expect(item.id.trim(), isNotEmpty);
    });

    test('ID contains the file path', () {
      const path = '/tmp/photo.jpg';
      final item = QueueItem(file: File(path), kind: FileKind.image);
      expect(item.id, contains(path));
    });

    test('two items with different paths have different IDs', () {
      final a = QueueItem(file: File('/tmp/a.mp4'), kind: FileKind.video);
      final b = QueueItem(file: File('/tmp/b.mp4'), kind: FileKind.video);
      expect(a.id, isNot(equals(b.id)));
    });

    test('two items with the same path created at different times have different IDs', () async {
      final a = QueueItem(file: File('/tmp/same.mp4'), kind: FileKind.video);
      await Future<void>.delayed(const Duration(microseconds: 5));
      final b = QueueItem(file: File('/tmp/same.mp4'), kind: FileKind.video);
      // IDs include microsecond timestamp so they must differ
      expect(a.id, isNot(equals(b.id)));
    });
  });

  group('QueueItem — mutable state transitions', () {
    test('status can be updated to compressing', () {
      final item = QueueItem(file: File('/tmp/v.mp4'), kind: FileKind.video);
      item.status = QueueStatus.compressing;
      expect(item.status, QueueStatus.compressing);
    });

    test('status can be updated to done', () {
      final item = QueueItem(file: File('/tmp/v.mp4'), kind: FileKind.video);
      item.status = QueueStatus.done;
      expect(item.status, QueueStatus.done);
    });

    test('status can be updated to error', () {
      final item = QueueItem(file: File('/tmp/v.mp4'), kind: FileKind.video);
      item.status = QueueStatus.error;
      item.errorMessage = 'Something went wrong';
      expect(item.status, QueueStatus.error);
      expect(item.errorMessage, 'Something went wrong');
    });

    test('status can be updated to cancelled', () {
      final item = QueueItem(file: File('/tmp/v.mp4'), kind: FileKind.video);
      item.status = QueueStatus.cancelled;
      expect(item.status, QueueStatus.cancelled);
    });

    test('progress can be updated', () {
      final item = QueueItem(file: File('/tmp/v.mp4'), kind: FileKind.video);
      item.progress = 0.42;
      expect(item.progress, closeTo(0.42, 0.001));
    });

    test('statusMessage can be updated', () {
      final item = QueueItem(file: File('/tmp/v.mp4'), kind: FileKind.video);
      item.statusMessage = 'Compressing video… 55%';
      expect(item.statusMessage, 'Compressing video… 55%');
    });

    test('result can be assigned', () {
      final item = QueueItem(file: File('/tmp/v.mp4'), kind: FileKind.video);
      const result = CompressionResult(
        outputPath: '/out/v_compressed.mp4',
        originalBytes: 1000,
        compressedBytes: 500,
        improved: true,
        note: '',
      );
      item.result = result;
      expect(item.result, result);
      expect(item.result!.reductionPercent, closeTo(50.0, 0.001));
    });
  });

  group('QueueItem — all FileKind values are accepted', () {
    for (final kind in FileKind.values) {
      test('accepts kind $kind', () {
        final item = QueueItem(file: File('/tmp/file'), kind: kind);
        expect(item.kind, kind);
      });
    }
  });
}
