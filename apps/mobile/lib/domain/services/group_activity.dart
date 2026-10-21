import 'package:arena_ops/domain/entities/activity.dart';

/// The station type a group session plays on: an active type that uses both
/// controllers and games — the console type the owner set up on the dashboard
/// ("PS5" in the demo catalog, but owners choose their own codes).
///
/// [prefer] lists codes to take first when they qualify: the tapped station's
/// types, or the type the group already plays. Otherwise the first eligible
/// type in the catalog's order. Null when the arena has no such type, so the
/// screen can say what is missing instead of offering stations it cannot use.
String? groupActivityCode(
  List<Activity> activities, {
  Iterable<String> prefer = const [],
}) {
  final eligible = [
    for (final a in activities)
      if (a.active && a.usesControllers && a.usesGames) a.code,
  ];
  for (final code in prefer) {
    if (eligible.contains(code)) return code;
  }
  return eligible.isEmpty ? null : eligible.first;
}
