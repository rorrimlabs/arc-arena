import 'package:arena_ops/domain/entities/game.dart';
import 'package:arena_ops/domain/entities/resource.dart';

/// Games that can be played for a station type: marked playable on at least one station
/// offering that type. Staff can start a game only where it is marked playable (the server
/// checks the same at session start), so a booking offers the same games.
Set<String> gamesPlayableForActivity(
  String activityCode,
  List<GameResource> compatibility,
  List<Resource> resources,
) {
  final stations = {
    for (final r in resources)
      if (r.activityCodes.contains(activityCode)) r.id,
  };
  return {
    for (final c in compatibility)
      if (c.status.isPlayable && stations.contains(c.resourceId)) c.gameId,
  };
}
