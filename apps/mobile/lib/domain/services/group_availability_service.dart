/// Group resource-sharing rules (group feature §5–§7). Pure Dart.
///
/// Unlike a single session — where a resource hosts at most one open segment —
/// a group may put several players on one PS5 at once (local multiplayer), but
/// ONLY when they are the same group playing the same game, bounded by the
/// game's max local players and the station's controller capacity. A resource a
/// group is using still blocks any single session and any other group, and vice
/// versa; single-session occupancy is passed in as [singleOccupancies].
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:arena_ops/domain/value/enums.dart';

class GroupAvailabilityService {
  const GroupAvailabilityService({this.portCapacity = 4});

  /// Controller ports the station hardware can fill at once (PS5 = 4). A
  /// property of the console, not of the inventory.
  final int portCapacity;

  /// Whether [groupId] may put a player on [resourceId] for [window] with the
  /// given game/activity/controllers, given everything already open there.
  ///
  /// [openOnResource] are the group-assignment rows currently open on this
  /// resource (any group); the caller excludes the player's own current open
  /// assignment via [excludePlayerNumber] when they are staying put (a game or
  /// controller change on the same system).
  Result<void> canAssign({
    required String resourceId,
    required String resourceName,
    required String groupId,
    required String activityCode,
    String? gameId,
    required int controllerCount,

    /// Usable controllers physically present at this station right now.
    /// Distinct from [portCapacity]: a PS5 has four ports but may only have
    /// two working pads on it.
    required int usableControllers,
    required GameAvailability gameAvailability,
    required int maxLocalPlayers,
    String? gameName,
    required bool activityAllowsSharing,
    required Iterable<Occupancy> singleOccupancies,
    required Iterable<GroupAssignment> openOnResource,
    required int playerNumber,
    int? excludePlayerNumber,
    required UtcInterval window,
    required DateTime closeAt,
    required bool allowPastClose,
  }) {
    if (!allowPastClose && window.end.isAfter(closeAt)) {
      return Err(Failure(
        message: "Can't start past closing time (${IstTime.format12(closeAt)}).",
        fix: 'Shorten the group session.',
        code: 'past_close',
      ));
    }

    // A chosen game must be playable on this system (group feature §6).
    if (gameId != null && gameAvailability != GameAvailability.playable) {
      return Err(Failure(
        message: '$resourceName can\'t run this game (${gameAvailability.label}).',
        fix: 'Pick a system where the game is playable, or change the game.',
        code: 'not_playable',
      ));
    }

    // A single session using this resource always blocks a group (group §7).
    for (final occ in singleOccupancies) {
      if (occ.resourceId == resourceId && occ.interval.overlaps(window)) {
        return Err(Failure(
          message: '$resourceName is in use'
              '${occ.label == null ? '' : ' by ${occ.label}'}.',
          fix: 'Pick another system.',
          code: 'resource_busy',
        ));
      }
    }

    final others = [
      for (final a in openOnResource)
        if (a.resourceId == resourceId &&
            !(a.groupId == groupId &&
                excludePlayerNumber != null &&
                a.playerNumber == excludePlayerNumber))
          a,
    ];
    if (others.isEmpty) {
      // Nothing else is here, but the station still needs enough working pads.
      return _checkControllers(
        resourceName: resourceName,
        used: 0,
        requested: controllerCount,
        usableControllers: usableControllers,
        gameLimit: _gameLimit(
          gameId: gameId,
          gameName: gameName,
          resourceName: resourceName,
          maxLocalPlayers: maxLocalPlayers,
          controllersOnStation: controllerCount,
        ),
      );
    }

    // Something is already on this system. Another group never shares.
    if (others.any((a) => a.groupId != groupId)) {
      return Err(Failure(
        message: '$resourceName is in use by another group.',
        fix: 'Pick another system.',
        code: 'resource_busy',
      ));
    }

    // Same group, but only PS5-style stations allow multiple players at once.
    if (!activityAllowsSharing) {
      return Err(Failure(
        message: '$resourceName is already in use by this group.',
        fix: 'Pick another system.',
        code: 'resource_busy',
      ));
    }

    // Co-located players must be on the same game and activity (group §6).
    if (others.any((a) => a.activityCode != activityCode || a.gameId != gameId)) {
      return Err(Failure(
        message: 'Players sharing $resourceName must play the same game.',
        fix: 'Match the game already running on $resourceName, or pick another system.',
        code: 'game_conflict',
      ));
    }

    // Bound by the game's local-multiplayer capacity.
    final players = {
      for (final a in others) a.playerNumber,
      playerNumber,
    };
    if (players.length > maxLocalPlayers) {
      return Err(Failure(
        message: 'This game supports up to $maxLocalPlayers local players on one system.',
        fix: 'Move a player to another system.',
        code: 'players_exceeded',
      ));
    }

    final usedControllers =
        others.fold<int>(0, (sum, a) => sum + (a.controllerCount ?? 0));
    return _checkControllers(
      resourceName: resourceName,
      used: usedControllers,
      requested: controllerCount,
      usableControllers: usableControllers,
      gameLimit: _gameLimit(
        gameId: gameId,
        gameName: gameName,
        resourceName: resourceName,
        maxLocalPlayers: maxLocalPlayers,
        controllersOnStation: usedControllers + controllerCount,
      ),
    );
  }

  /// Every controller on a station is a local player slot, so the game's
  /// local-player limit bounds the controllers on the station — the same rule
  /// a single session already follows ("This game supports N local players").
  /// Without a chosen game there is no limit to apply.
  Failure? _gameLimit({
    required String? gameId,
    required String? gameName,
    required String resourceName,
    required int maxLocalPlayers,
    required int controllersOnStation,
  }) {
    if (gameId == null || controllersOnStation <= maxLocalPlayers) return null;
    return Failure(
      message: '${gameName ?? 'This game'} supports $maxLocalPlayers local '
          'player${maxLocalPlayers == 1 ? '' : 's'} — $controllersOnStation '
          'controllers on $resourceName.',
      fix: 'Use fewer controllers on $resourceName, or move a player to '
          'another system.',
      code: 'players_exceeded',
    );
  }

  /// Three limits, checked in this order because they need different fixes:
  /// the console's ports are a hardware ceiling, the game's local-player limit
  /// ([gameLimit]) is a rule of the chosen game, and usable pads are an
  /// inventory shortfall a staff member can walk across the floor and fix.
  Result<void> _checkControllers({
    required String resourceName,
    required int used,
    required int requested,
    required int usableControllers,
    Failure? gameLimit,
  }) {
    if (used + requested > portCapacity) {
      return Err(Failure(
        message: '$resourceName can hold up to $portCapacity controllers.',
        fix: 'Reduce controllers or use another system.',
        code: 'controllers_exceeded',
      ));
    }
    if (gameLimit != null) return Err(gameLimit);
    if (used + requested > usableControllers) {
      return Err(Failure(
        message: '$resourceName has only $usableControllers usable '
            'controller${usableControllers == 1 ? '' : 's'}'
            '${used == 0 ? '' : ' ($used already in use)'}.',
        fix: 'Move a controller to $resourceName, or use another system.',
        code: 'controllers_unavailable',
      ));
    }
    return const Ok(null);
  }
}
