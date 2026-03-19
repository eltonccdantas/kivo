import 'package:flutter/material.dart';

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
  String _etaText(double progress) {
    final start = _startTime;
    if (start == null || progress <= 0.05 || progress >= 0.98) return '';

    final elapsed = DateTime.now().difference(start).inSeconds;
    if (elapsed < 4) return ''; // avoid wild estimates in the first few seconds

    final totalEstimated = elapsed / progress;
    final remaining = (totalEstimated * (1 - progress)).round();

    if (remaining <= 5) return 'Almost done…';
    if (remaining < 60) return '~$remaining s remaining';
    final mins = (remaining / 60).ceil();
    return '~$mins min remaining';
  }

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

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 24),
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
                valueListenable: widget.progress,
                builder: (_, value, __) {
                  final pct = (value * 100).toStringAsFixed(0);
                  final eta = _etaText(value);
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
                          backgroundColor:
                              scheme.primary.withValues(alpha: 0.15),
                          color: scheme.primary,
                        ),
                      ),
                      // ETA label — only rendered when estimable.
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
                const SizedBox(height: 24),
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
