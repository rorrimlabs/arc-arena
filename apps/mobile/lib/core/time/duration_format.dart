/// Formats durations for the big on-card timers. Monospace/tabular digits in
/// the theme keep these from jittering.
library;

/// `M:SS` under an hour, `H:MM:SS` at or above. Negative durations are shown as
/// their magnitude (callers add their own +/− label).
String formatClock(Duration d) {
  final total = d.inSeconds.abs();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// `1h 30m`, `45m`, `0m` — compact minutes for durations/extensions.
String formatMinutesLabel(Duration d) {
  final total = d.inMinutes.abs();
  final h = total ~/ 60;
  final m = total % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}
