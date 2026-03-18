import 'package:flutter/material.dart';

class ProgressDialog extends StatelessWidget {
  final ValueNotifier<double> progress;
  final ValueNotifier<String> statusMessage;

  const ProgressDialog({
    super.key,
    required this.progress,
    required this.statusMessage,
  });

  static Future<void> show(
    BuildContext context, {
    required ValueNotifier<double> progress,
    required ValueNotifier<String> statusMessage,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProgressDialog(
        progress: progress,
        statusMessage: statusMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Compressing…',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 32),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, __) {
                  final pct = (value * 100).toStringAsFixed(0);
                  return Column(
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: value > 0 ? value : null,
                                strokeWidth: 8,
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.15),
                                color: scheme.primary,
                              ),
                            ),
                            Text(
                              value > 0 ? '$pct%' : '…',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: value > 0 ? value : null,
                          minHeight: 6,
                          backgroundColor: scheme.primary.withValues(alpha: 0.15),
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
