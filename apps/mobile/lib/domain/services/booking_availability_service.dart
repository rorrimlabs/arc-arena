/// Game-first booking availability (spec §19–§21, §24). Pure Dart.
///
/// Finds systems that can run a game for the WHOLE requested period, are
/// operational, and have no conflicting session or booking. Also validates a
/// specific requested system with a precise reason when it cannot be booked.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:arena_ops/domain/value/enums.dart';

class BookingAvailabilityService {
  const BookingAvailabilityService();

  /// Systems that can host [requireActivityCode] for the full [window]:
  /// operational, game-compatible (if [compatibility] is given), free of any
  /// conflicting occupancy, and meeting the player requirement.
  List<Resource> availableSystems({
    required UtcInterval window,
    required List<Resource> resources,
    required Iterable<Occupancy> occupancies,
    required String requireActivityCode,
    Map<String, GameAvailability>? compatibility,
    int? gameMaxLocalPlayers,
    int? playersRequired,
  }) {
    // Player requirement is a game-level fact (same for every station).
    if (playersRequired != null &&
        gameMaxLocalPlayers != null &&
        gameMaxLocalPlayers < playersRequired) {
      return const [];
    }
    return resources
        .where((r) => _isFree(
              resource: r,
              window: window,
              occupancies: occupancies,
              requireActivityCode: requireActivityCode,
              compatibility: compatibility,
            ))
        .toList();
  }

  bool _isFree({
    required Resource resource,
    required UtcInterval window,
    required Iterable<Occupancy> occupancies,
    required String requireActivityCode,
    Map<String, GameAvailability>? compatibility,
  }) {
    if (resource.status != ResourceStatus.available) return false;
    if (!resource.activityCodes.contains(requireActivityCode)) return false;
    if (compatibility != null &&
        !(compatibility[resource.id]?.isPlayable ?? false)) {
      return false;
    }
    for (final occ in occupancies) {
      if (occ.resourceId == resource.id && occ.interval.overlaps(window)) {
        return false;
      }
    }
    return true;
  }

  /// Validate a SPECIFIC requested system (spec §20B, §21) with a clear reason.
  Result<void> checkSpecific({
    required Resource resource,
    required UtcInterval window,
    required Iterable<Occupancy> occupancies,
    required String requireActivityCode,
    String? gameName,
    Map<String, GameAvailability>? compatibility,
    int? gameMaxLocalPlayers,
    int? playersRequired,
  }) {
    if (resource.status != ResourceStatus.available) {
      return Err(Failure(
        message: '${resource.name} is ${resource.status.name}.',
        fix: 'Pick another system.',
        code: 'not_operational',
      ));
    }
    if (!resource.activityCodes.contains(requireActivityCode)) {
      return Err(Failure(
        message: '${resource.name} does not support $requireActivityCode.',
        code: 'activity_unsupported',
      ));
    }
    if (compatibility != null &&
        !(compatibility[resource.id]?.isPlayable ?? false)) {
      return Err(Failure(
        message: '${gameName ?? 'That game'} is not playable on ${resource.name}.',
        code: 'game_incompatible',
      ));
    }
    if (playersRequired != null &&
        gameMaxLocalPlayers != null &&
        gameMaxLocalPlayers < playersRequired) {
      return Err(Failure(
        message: '${gameName ?? 'That game'} supports up to '
            '$gameMaxLocalPlayers players.',
        code: 'players_exceeded',
      ));
    }
    for (final occ in occupancies) {
      if (occ.resourceId == resource.id && occ.interval.overlaps(window)) {
        return Err(Failure(
          message: '${resource.name} is occupied during the requested time.',
          fix: 'Pick another system or time.',
          code: 'occupied',
        ));
      }
    }
    return const Ok(null);
  }
}

/// Convenience: a booking window from an IST date + start/duration.
UtcInterval bookingWindow({
  required IstDate date,
  required int startMinuteOfDay,
  required int durationMinutes,
}) {
  final start = IstTime(date.year, date.month, date.day, 0, 0)
      .toUtc()
      .add(Duration(minutes: startMinuteOfDay));
  return UtcInterval(start, start.add(Duration(minutes: durationMinutes)));
}
