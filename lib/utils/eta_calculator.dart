/// Returns a human-readable ETA string given [progress] (0..1),
/// the [startTime] when progress first became meaningful,
/// and [now] as the current instant (injectable for testing).
///
/// Returns an empty string when the estimate is not yet reliable
/// (too early, too close to the start, or nearly done).
String calculateEta(double progress, DateTime? startTime, DateTime now) {
  if (startTime == null || progress <= 0.05 || progress >= 0.98) return '';

  final elapsed = now.difference(startTime).inSeconds;
  if (elapsed < 4) return ''; // too early — estimate would be noisy

  final totalEstimated = elapsed / progress;
  final remaining = (totalEstimated * (1 - progress)).round();

  if (remaining <= 5) return 'Almost done…';
  if (remaining < 60) return '~$remaining s remaining';
  final mins = (remaining / 60).ceil();
  return '~$mins min remaining';
}
