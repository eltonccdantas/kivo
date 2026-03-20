import 'package:flutter/material.dart';
import '../utils/eta_calculator.dart';

class ProgressDialog extends StatefulWidget {
  final ValueNotifier<double> progress;
  final ValueNotifier<String> statusMessage;
  final VoidCallback? onCancelRequested;

  const ProgressDialog({
    super.key,
    required this.progress,
    required this.statusMessage,
    this.onCancelRequested,
  });

  static Future<void> show(
    BuildContext context, {
    required ValueNotifier<double> progress,
    required ValueNotifier<String> statusMessage,
    VoidCallback? onCancelRequested,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProgressDialog(
        progress: progress,
        statusMessage: statusMessage,
        onCancelRequested: onCancelRequested,
      ),
    );
  }

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onProgress);
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    super.dispose();
  }

  void _onProgress() {
    // Record start time on first meaningful progress tick.
    if (_startTime == null && widget.progress.value > 0.05) {
      setState(() => _startTime = DateTime.now());
    }
  }

  /// Returns a human-readable ETA string, or empty string when not yet
  /// estimable (too early) or no longer needed (almost done).
  String _etaText(double progress) =>
      calculateEta(progress, _startTime, DateTime.now());

  Future<void> _confirmCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Cancel compression?',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          content: Text(
            'All compression progress will be lost and you will need to start over.',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No, continue'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              child: const Text('Yes, cancel'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      widget.onCancelRequested?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    // Compact mode when the available height is small (landscape phones).
    final compact = mq.size.height < 500;
    final circleSize = compact ? 72.0 : 100.0;
    final circleFont = compact ? 17.0 : 22.0;
    final innerPadding = compact
        ? const EdgeInsets.fromLTRB(28, 20, 28, 16)
        : const EdgeInsets.fromLTRB(32, 36, 32, 24);
    final gap1 = compact ? 16.0 : 32.0;
    final gap2 = compact ? 16.0 : 24.0;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        // Tighter vertical inset in landscape so the dialog has more room.
        insetPadding: EdgeInsets.symmetric(
          horizontal: 40,
          vertical: compact ? 12 : 24,
        ),
        child: SingleChildScrollView(
          padding: innerPadding,
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
              SizedBox(height: gap1),
              ValueListenableBuilder<double>(
                valueListenable: widget.progress,
                builder: (_, value, __) {
                  final pct = (value * 100).toStringAsFixed(0);
                  final eta = _etaText(value);
                  return Column(
                    children: [
                      SizedBox(
                        width: circleSize,
                        height: circleSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: value > 0 ? value : null,
                                strokeWidth: compact ? 6 : 8,
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.15),
                                color: scheme.primary,
                              ),
                            ),
                            Text(
                              value > 0 ? '$pct%' : '…',
                              style: TextStyle(
                                fontSize: circleFont,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: gap2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: value > 0 ? value : null,
                          minHeight: 6,
                          backgroundColor:
                              scheme.primary.withValues(alpha: 0.15),
                          color: scheme.primary,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        child: eta.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  eta,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
              if (widget.onCancelRequested != null) ...[
                SizedBox(height: gap2),
                TextButton(
                  onPressed: () => _confirmCancel(context),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
