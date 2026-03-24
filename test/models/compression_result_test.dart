import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/models/models.dart';

void main() {
  group('CompressionResult.reductionPercent', () {
    test('0 % when sizes are equal', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 1000,
        compressedBytes: 1000,
        improved: false,
        note: '',
      );
      expect(r.reductionPercent, 0.0);
    });

    test('50 % reduction', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 1000,
        compressedBytes: 500,
        improved: true,
        note: '',
      );
      expect(r.reductionPercent, closeTo(50.0, 0.001));
    });

    test('75 % reduction', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 4000,
        compressedBytes: 1000,
        improved: true,
        note: '',
      );
      expect(r.reductionPercent, closeTo(75.0, 0.001));
    });

    test('clamps to 0 when compressed is larger than original', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 1000,
        compressedBytes: 2000,
        improved: false,
        note: '',
      );
      expect(r.reductionPercent, 0.0);
    });

    test('clamps to 100 when compressedBytes is 0', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 1000,
        compressedBytes: 0,
        improved: true,
        note: '',
      );
      expect(r.reductionPercent, 100.0);
    });

    test('returns 0.0 when originalBytes is 0 (no division by zero)', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 0,
        compressedBytes: 0,
        improved: false,
        note: '',
      );
      expect(r.reductionPercent, 0.0);
    });

    test('1 % reduction', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 10000,
        compressedBytes: 9900,
        improved: true,
        note: '',
      );
      expect(r.reductionPercent, closeTo(1.0, 0.001));
    });

    test('99 % reduction is below 100', () {
      const r = CompressionResult(
        outputPath: '/out.jpg',
        originalBytes: 10000,
        compressedBytes: 100,
        improved: true,
        note: '',
      );
      expect(r.reductionPercent, closeTo(99.0, 0.001));
    });

    test('stores all fields correctly', () {
      const r = CompressionResult(
        outputPath: '/tmp/output.mp4',
        originalBytes: 5000,
        compressedBytes: 2500,
        improved: true,
        note: 'Re-encoded with HEVC.',
      );
      expect(r.outputPath, '/tmp/output.mp4');
      expect(r.originalBytes, 5000);
      expect(r.compressedBytes, 2500);
      expect(r.improved, true);
      expect(r.note, 'Re-encoded with HEVC.');
    });
  });

  group('FileKind', () {
    test('has exactly 4 values', () {
      expect(FileKind.values.length, 4);
    });

    test('contains expected members', () {
      expect(
        FileKind.values,
        containsAll([
          FileKind.image,
          FileKind.video,
          FileKind.pdf,
          FileKind.unsupported,
        ]),
      );
    });

    test('all values are distinct', () {
      final values = FileKind.values;
      expect(values.toSet().length, values.length);
    });
  });
}
