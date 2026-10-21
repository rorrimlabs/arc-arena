import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:arena_ops/domain/services/group_availability_service.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const svc = GroupAvailabilityService();
  final start = ist(2026, 10, 2, 18, 0);
  final window = UtcInterval(start, start.add(const Duration(minutes: 60)));
  final closeAt = ist(2026, 10, 2, 23, 0);

  GroupAssignment open(int player, String res,
          {String group = 'g1', String? game = 'g_wwe', int ctrl = 1}) =>
      GroupAssignment(
        id: 'a${player}_$res',
        groupId: group,
        playerNumber: player,
        index: 0,
        resourceId: res,
        activityCode: 'PS5',
        gameId: game,
        controllerCount: ctrl,
        startedAt: start,
        createdAt: start,
      );

  // Convenience wrapper with the common PS5 defaults.
  dynamic can({
    String resource = 'hex',
    String group = 'g1',
    String? game = 'g_wwe',
    int controllers = 1,
    /// A whole PS5 station: four ports, four working pads. Keeps every
    /// pre-inventory case asserting exactly what it asserted before.
    int usableControllers = 4,
    GameAvailability availability = GameAvailability.playable,
    int maxLocalPlayers = 4,
    bool sharing = true,
    List<Occupancy> single = const [],
    List<GroupAssignment> onResource = const [],
    int player = 2,
    int? excludePlayer,
  }) =>
      svc.canAssign(
        resourceId: resource,
        resourceName: resource.toUpperCase(),
        groupId: group,
        activityCode: 'PS5',
        gameId: game,
        controllerCount: controllers,
        usableControllers: usableControllers,
        gameAvailability: availability,
        maxLocalPlayers: maxLocalPlayers,
        activityAllowsSharing: sharing,
        singleOccupancies: single,
        openOnResource: onResource,
        playerNumber: player,
        excludePlayerNumber: excludePlayer,
        window: window,
        closeAt: closeAt,
        allowPastClose: false,
      );

  test('a free, compatible system is assignable', () {
    expect(can().isOk, isTrue);
  });

  test('an unplayable game is rejected', () {
    expect(can(availability: GameAvailability.notPlayable).failureOrNull?.code,
        'not_playable');
  });

  test('a single session on the system blocks the group', () {
    expect(
      can(single: [
        Occupancy(resourceId: 'hex', interval: window, isBooking: false)
      ]).failureOrNull?.code,
      'resource_busy',
    );
  });

  test('another group on the system blocks it', () {
    expect(
      can(onResource: [open(1, 'hex', group: 'g2')]).failureOrNull?.code,
      'resource_busy',
    );
  });

  test('the same group playing the same game may co-locate', () {
    expect(can(onResource: [open(1, 'hex')]).isOk, isTrue);
  });

  test('co-locating a different game is a conflict', () {
    expect(
      can(onResource: [open(1, 'hex', game: 'g_wwe')], game: 'g_mk1')
          .failureOrNull
          ?.code,
      'game_conflict',
    );
  });

  test('exceeding the game max local players is rejected', () {
    expect(
      can(
        onResource: [open(1, 'hex'), open(2, 'hex')],
        player: 3,
        maxLocalPlayers: 2,
      ).failureOrNull?.code,
      'players_exceeded',
    );
  });

  test('exceeding the station controller capacity is rejected', () {
    expect(
      can(onResource: [open(1, 'hex', ctrl: 3)], controllers: 2)
          .failureOrNull
          ?.code,
      'controllers_exceeded',
    );
  });

  group('ports and usable pads are different limits', () {
    test('five controllers on a whole station is a hardware ceiling', () {
      // Four ports, eight pads lying around: still four.
      final r = can(controllers: 5, usableControllers: 8);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'controllers_exceeded');
      expect(r.failureOrNull!.message, contains('up to 4 controllers'));
    });

    test('three controllers on a two-pad station is a supply shortfall', () {
      final r = can(controllers: 3, usableControllers: 2);
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'controllers_unavailable');
      expect(r.failureOrNull!.message, contains('only 2 usable controllers'));
      // The fix must name the way out, not just restate the problem.
      expect(r.failureOrNull!.fix, contains('Move a controller'));
    });

    test('the shortfall counts what is already in use on the station', () {
      // Two pads, one already on a seated player, a second player wants two.
      final r = can(
        controllers: 2,
        usableControllers: 2,
        onResource: [open(1, 'hex', ctrl: 1)],
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.code, 'controllers_unavailable');
      expect(r.failureOrNull!.message, contains('(1 already in use)'));
    });

    test('a station with exactly enough pads is allowed', () {
      expect(can(controllers: 2, usableControllers: 2).isOk, isTrue);
    });

    test('a faulty pad is felt even on an empty station', () {
      // One pad works; a single player is fine, a pair is not.
      expect(can(controllers: 1, usableControllers: 1).isOk, isTrue);
      final pair = can(controllers: 2, usableControllers: 1);
      expect(pair.isErr, isTrue);
      expect(pair.failureOrNull!.code, 'controllers_unavailable');
      expect(pair.failureOrNull!.message, contains('only 1 usable controller'),
          reason: 'singular, not "1 usable controllers"');
    });
  });

  test('a non-shareable activity cannot be co-located', () {
    expect(
      can(
        resource: 'pool1',
        game: null,
        sharing: false,
        onResource: [open(1, 'pool1', game: null)],
      ).failureOrNull?.code,
      'resource_busy',
    );
  });

  test('staying put (controller change) ignores the player\'s own spot', () {
    expect(
      can(onResource: [open(1, 'hex')], player: 1, excludePlayer: 1).isOk,
      isTrue,
    );
  });
}
