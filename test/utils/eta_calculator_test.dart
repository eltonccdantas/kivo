import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/utils/eta_calculator.dart';

void main() {
  // Fixed reference instant used across all tests.
  final t0 = DateTime(2024, 1, 1, 12, 0, 0);

  DateTime ago(int seconds) => t0.subtract(Duration(seconds: seconds));

  group('calculateEta — returns empty string when estimate is unreliable', () {
    test('null startTime → empty', () {
      expect(calculateEta(0.5, null, t0), '');
    });

    test('progress = 0 → empty', () {
      expect(calculateEta(0.0, ago(10), t0), '');
    });

    test('progress ≤ 0.05 → empty', () {
      expect(calculateEta(0.05, ago(10), t0), '');
    });

    test('progress ≥ 0.98 → empty (nearly done, no ETA needed)', () {
      expect(calculateEta(0.98, ago(10), t0), '');
      expect(calculateEta(1.0, ago(10), t0), '');
    });

    test('elapsed < 4 s → empty (too early, estimate would be noisy)', () {
      expect(calculateEta(0.5, ago(3), t0), '');
      expect(calculateEta(0.5, ago(0), t0), '');
    });
  });

  group('calculateEta — "Almost done…"', () {
    test('remaining ≤ 5 s → "Almost done…"', () {
      // 10 s elapsed at 50 % → total ~20 s → remaining ~10 s… adjust to get ≤5
      // 20 s elapsed at 80 % → total ~25 s → remaining ~5 s
      expect(calculateEta(0.80, ago(20), t0), 'Almost done…');
    });

    test('remaining exactly 5 s → "Almost done…"', () {
      // 95 s elapsed at 95 % → total ~100 s → remaining ~5 s
      expect(calculateEta(0.95, ago(95), t0), 'Almost done…');
    });
  });

  group('calculateEta — seconds format', () {
    test('~30 s remaining', () {
      // 30 s elapsed at 50 % → total 60 s → remaining 30 s
      expect(calculateEta(0.5, ago(30), t0), '~30 s remaining');
    });

    test('~10 s remaining', () {
      // 45 s elapsed at 82 % → total ~54.9 s → remaining ~9.9 ≈ 10 s
      expect(calculateEta(0.82, ago(45), t0), '~10 s remaining');
    });

    test('remaining = 59 s stays in seconds', () {
      // 41 s elapsed at 41 % → total 100 s → remaining 59 s
      expect(calculateEta(0.41, ago(41), t0), '~59 s remaining');
    });
  });

  group('calculateEta — minutes format', () {
    test('~1 min remaining', () {
      // 60 s elapsed at 50 % → total 120 s → remaining 60 s → 1 min
      expect(calculateEta(0.5, ago(60), t0), '~1 min remaining');
    });

    test('~2 min remaining', () {
      // 120 s elapsed at 50 % → total 240 s → remaining 120 s → 2 min
      expect(calculateEta(0.5, ago(120), t0), '~2 min remaining');
    });

    test('fractional minutes round up', () {
      // 90 s elapsed at 50 % → total 180 s → remaining 90 s → ceil(1.5) = 2 min
      expect(calculateEta(0.5, ago(90), t0), '~2 min remaining');
    });

    test('61 s remaining → 2 min (ceil)', () {
      // remaining 61 s → ceil(61/60) = 2 min
      // 61 s elapsed at 50 % → total 122 s → remaining 61 s
      expect(calculateEta(0.5, ago(61), t0), '~2 min remaining');
    });
  });

  group('calculateEta — boundary between seconds and minutes', () {
    test('remaining = 60 s is displayed as minutes, not seconds', () {
      final result = calculateEta(0.5, ago(60), t0);
      expect(result, contains('min'));
    });

    test('remaining = 59 s is displayed as seconds, not minutes', () {
      final result = calculateEta(0.41, ago(41), t0);
      expect(result, contains('s remaining'));
      expect(result, isNot(contains('min')));
    });
  });
}
