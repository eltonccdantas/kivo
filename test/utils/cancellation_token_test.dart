import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/utils/cancellation_token.dart';

void main() {
  group('CancellationToken', () {
    test('starts not cancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, false);
    });

    test('cancel() marks as cancelled', () {
      final token = CancellationToken();
      token.cancel();
      expect(token.isCancelled, true);
    });

    test('multiple cancel() calls are idempotent', () {
      final token = CancellationToken();
      token.cancel();
      token.cancel();
      token.cancel();
      expect(token.isCancelled, true);
    });

    test('independent tokens do not share state', () {
      final a = CancellationToken();
      final b = CancellationToken();
      a.cancel();
      expect(a.isCancelled, true);
      expect(b.isCancelled, false);
    });

    test('multiple tokens can all be cancelled independently', () {
      final tokens = List.generate(5, (_) => CancellationToken());
      tokens[1].cancel();
      tokens[3].cancel();
      for (var i = 0; i < tokens.length; i++) {
        expect(tokens[i].isCancelled, i == 1 || i == 3);
      }
    });
  });

  group('CompressionCancelledException', () {
    test('can be thrown and caught as Exception', () {
      expect(
        () => throw const CompressionCancelledException(),
        throwsA(isA<CompressionCancelledException>()),
      );
    });

    test('is an Exception', () {
      const e = CompressionCancelledException();
      expect(e, isA<Exception>());
    });

    test('const instances are equal', () {
      const a = CompressionCancelledException();
      const b = CompressionCancelledException();
      expect(identical(a, b), true);
    });

    test('caught by generic Exception handler', () {
      Object? caught;
      try {
        throw const CompressionCancelledException();
      } on Exception catch (e) {
        caught = e;
      }
      expect(caught, isA<CompressionCancelledException>());
    });
  });
}
