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

/// What a price is per, after the slash: `h`, `30 min`, `2 h`, `day`, `3 days`
/// (rates can be per any whole number of minutes, hours or days).
String formatPerUnit(int unitMinutes) {
  if (unitMinutes > 0 && unitMinutes % 1440 == 0) {
    final days = unitMinutes ~/ 1440;
    return days == 1 ? 'day' : '$days days';
  }
  if (unitMinutes > 0 && unitMinutes % 60 == 0) {
    final hours = unitMinutes ~/ 60;
    return hours == 1 ? 'h' : '$hours h';
  }
  return '$unitMinutes min';
}
