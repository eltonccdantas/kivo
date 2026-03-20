import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/widgets/progress_dialog.dart';

/// Pumps a minimal app and returns a [BuildContext] captured outside the
/// build phase. Showing a dialog inside a Builder's build method would
/// re-call showDialog on every rebuild (e.g., triggered by a tap event),
/// which causes the first dialog to be dismissed unexpectedly.
Future<BuildContext> _buildAndGetContext(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    home: Scaffold(
      body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.shrink();
      }),
    ),
  ));
  await tester.pump();
  return ctx;
}

void main() {
  group('ProgressDialog — rendering', () {
    testWidgets('shows "Compressing…" title', (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');
      addTearDown(() {
        progress.dispose();
        status.dispose();
      });

      final ctx = await _buildAndGetContext(tester);
      ProgressDialog.show(ctx, progress: progress, statusMessage: status);
      await tester.pump();

      expect(find.text('Compressing…'), findsOneWidget);
    });

    testWidgets('shows Cancel button when onCancelRequested is provided',
        (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');
      addTearDown(() {
        progress.dispose();
        status.dispose();
      });

      final ctx = await _buildAndGetContext(tester);
      ProgressDialog.show(
        ctx,
        progress: progress,
        statusMessage: status,
        onCancelRequested: () {},
      );
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('hides Cancel button when onCancelRequested is null',
        (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');
      addTearDown(() {
        progress.dispose();
        status.dispose();
      });

      final ctx = await _buildAndGetContext(tester);
      ProgressDialog.show(ctx, progress: progress, statusMessage: status);
      await tester.pump();

      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('shows "…" when progress is 0 (indeterminate)', (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');
      addTearDown(() {
        progress.dispose();
        status.dispose();
      });

      final ctx = await _buildAndGetContext(tester);
      ProgressDialog.show(ctx, progress: progress, statusMessage: status);
      await tester.pump();

      expect(find.text('…'), findsOneWidget);
    });

    testWidgets('displays percentage when progress > 0', (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');
      addTearDown(() {
        progress.dispose();
        status.dispose();
      });

      final ctx = await _buildAndGetContext(tester);
      ProgressDialog.show(ctx, progress: progress, statusMessage: status);
      await tester.pump();

      progress.value = 0.79;
      await tester.pump();

      expect(find.text('79%'), findsOneWidget);
    });

    testWidgets('progress updates rebuild the indicator', (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');
      addTearDown(() {
        progress.dispose();
        status.dispose();
      });

      final ctx = await _buildAndGetContext(tester);
      ProgressDialog.show(ctx, progress: progress, statusMessage: status);
      await tester.pump();

      expect(find.text('…'), findsOneWidget);

      progress.value = 0.42;
      await tester.pump();
      expect(find.text('42%'), findsOneWidget);

      progress.value = 0.99;
      await tester.pump();
      expect(find.text('99%'), findsOneWidget);
    });
  });

  group('ProgressDialog — cannot be dismissed by tapping barrier', () {
    testWidgets('dialog remains visible after tapping outside', (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');
      addTearDown(() {
        progress.dispose();
        status.dispose();
      });

      // Show the dialog AFTER the initial build so that taps do not
      // trigger a rebuild that would call showDialog() a second time.
      final ctx = await _buildAndGetContext(tester);
      ProgressDialog.show(ctx, progress: progress, statusMessage: status);
      await tester.pump();

      expect(find.text('Compressing…'), findsOneWidget);

      // Tap the barrier area (outside the dialog content).
      await tester.tapAt(const Offset(10, 10));
      // Use pump() rather than pumpAndSettle(): the indeterminate
      // CircularProgressIndicator animates forever, so pumpAndSettle times out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog must still be present — barrierDismissible is false.
      expect(find.text('Compressing…'), findsOneWidget);
    });
  });

  group('ProgressDialog — ValueNotifier listener lifecycle', () {
    // Regression test: progress.dispose() was called while the dialog's
    // ValueListenableBuilder still held an active listener. When the dialog's
    // State.dispose() later called removeListener on the already-disposed
    // notifier, Flutter threw an assertion error, closing the app.
    testWidgets(
        'dispose is safe after dialog fully unmounts '
        '(regression: disposed-notifier crash)', (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');

      final ctx = await _buildAndGetContext(tester);
      final dialogFuture = ProgressDialog.show(
        ctx,
        progress: progress,
        statusMessage: status,
      );
      await tester.pump();

      // Advance progress to ensure the listener is active.
      progress.value = 0.5;
      await tester.pump();

      // Close the dialog exactly as _compress() does.
      Navigator.of(ctx, rootNavigator: true).pop();
      // pumpAndSettle lets the exit animation finish → State.dispose() runs.
      await tester.pumpAndSettle();
      await dialogFuture;

      // All listeners removed. Dispose must NOT throw.
      expect(() => progress.dispose(), returnsNormally);
      expect(() => status.dispose(), returnsNormally);
    });

    testWidgets('no listeners remain after dialog closes', (tester) async {
      final progress = ValueNotifier<double>(0.0);
      final status = ValueNotifier<String>('');

      final ctx = await _buildAndGetContext(tester);
      final dialogFuture = ProgressDialog.show(
        ctx,
        progress: progress,
        statusMessage: status,
      );
      await tester.pump();

      Navigator.of(ctx, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      await dialogFuture;

      // If no listeners remain, dispose() will not throw an assertion.
      // This is the observable contract; Flutter asserts on remaining listeners.
      expect(() {
        progress.dispose();
        status.dispose();
      }, returnsNormally);
    });
  });
}
