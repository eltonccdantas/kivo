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

    test('NOT caught by a non-Exception catch block targeting a different type',
        () {
      Object? caught;
      try {
        throw const CompressionCancelledException();
      } on StateError catch (e) {
        caught = e;
      } catch (_) {}
      expect(caught, isNull);
    });
  });

  group('CancellationToken — poll-loop pattern (regression: infinite doWhile)',
      () {
    // The doWhile cancellation-poller in VideoService used to run forever
    // after the process exited because it only stopped on token.cancel().
    // This test verifies the equivalent pattern stops correctly via a flag.
    test('loop stops when processRunning flag is set to false', () async {
      var processRunning = true;
      var iterations = 0;

      await Future.doWhile(() async {
        if (!processRunning) return false;
        iterations++;
        if (iterations >= 3) {
          processRunning = false; // simulate process exit
        }
        return processRunning;
      });

      expect(processRunning, false);
      expect(iterations, 3);
    });

    test('loop body never runs when flag starts false', () async {
      var processRunning = false;
      var loopBodyReached = false;

      await Future.doWhile(() async {
        if (!processRunning) return false;
        loopBodyReached = true; // only reachable if flag were true
        return true;
      });

      expect(loopBodyReached, false);
    });

    test('token cancel stops loop before process exits', () async {
      final token = CancellationToken();
      var killed = false;
      var iterations = 0;

      // Cancel after a short delay to let at least one iteration run.
      Future.delayed(const Duration(milliseconds: 10), token.cancel);

      await Future.doWhile(() async {
        if (token.isCancelled) {
          killed = true;
          return false;
        }
        iterations++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return true;
      });

      expect(killed, true);
      expect(iterations, greaterThan(0));  // at least one iteration ran
      expect(iterations, lessThan(20));    // but the loop did not run forever
    });
  });
}
