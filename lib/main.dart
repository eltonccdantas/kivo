import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  // Catch Flutter framework errors (widget build errors, etc.)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  // Catch all unhandled async exceptions in the root zone — these would
  // otherwise silently close the app without any UI feedback.
  runZonedGuarded(
    () => runApp(const KivoApp()),
    (error, stack) {
      if (kDebugMode) {
        debugPrint('Unhandled async error: $error\n$stack');
      }
    },
  );
}
