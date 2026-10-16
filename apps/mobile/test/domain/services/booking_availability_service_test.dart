import 'package:arena_ops/core/time/utc_interval.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/services/availability_service.dart';
import 'package:arena_ops/domain/services/booking_availability_service.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const svc = BookingAvailabilityService();

  Resource res(String id, String name, {List<String> acts = const ['PS5'], ResourceStatus status = ResourceStatus.available}) =>
      Resource(id: id, name: name, kind: ResourceKind.station, status: status, activityCodes: acts);

  final resources = [
    res('hex', 'HEX'),
    res('void', 'VOID'),
    res('ghost', 'GHOST'),
    res('rift', 'RIFT', acts: ['PS5', 'VR']),
  ];

  // Requested 7:00–8:00 PM Friday.
  final window = UtcInterval(ist(2026, 10, 2, 19, 0), ist(2026, 10, 2, 20, 0));

  // EA FC playable everywhere for these tests.
  final playableEverywhere = {
    for (final r in resources) r.id: GameAvailability.playable,
  };

  Occupancy occ(String resId, int fromH, int fromM, int toH, int toM, {bool booking = false}) =>
      Occupancy(
        resourceId: resId,
        interval: UtcInterval(ist(2026, 10, 2, fromH, fromM), ist(2026, 10, 2, toH, toM)),
        isBooking: booking,
      );

  List<String> ids(List<Resource> r) => r.map((e) => e.id).toList();

  test('game-first availability over the full period (spec §19)', () {
    // HEX has an overlapping session; RIFT has an overlapping booking.
    final available = svc.availableSystems(
      window: window,
      resources: resources,
      occupancies: [occ('hex', 18, 30, 19, 30), occ('rift', 19, 0, 20, 0, booking: true)],
      requireActivityCode: 'PS5',
      compatibility: playableEverywhere,
    );
    expect(ids(available), ['void', 'ghost']);
  });

  test('incompatible game is excluded even when free', () {
    final compat = {...playableEverywhere, 'ghost': GameAvailability.notPlayable};
    final available = svc.availableSystems(
      window: window,
      resources: resources,
      occupancies: const [],
      requireActivityCode: 'PS5',
      compatibility: compat,
    );
    expect(ids(available), ['hex', 'void', 'rift']);
  });

  test('maintenance/disabled systems are excluded', () {
    final rs = [
      res('hex', 'HEX', status: ResourceStatus.maintenance),
      res('void', 'VOID', status: ResourceStatus.disabled),
      res('ghost', 'GHOST'),
    ];
    final available = svc.availableSystems(
      window: window,
      resources: rs,
      occupancies: const [],
      requireActivityCode: 'PS5',
      compatibility: {for (final r in rs) r.id: GameAvailability.playable},
    );
    expect(ids(available), ['ghost']);
  });

  test('a touching booking does not block (half-open period)', () {
    final available = svc.availableSystems(
      window: window,
      resources: [res('hex', 'HEX')],
      occupancies: [occ('hex', 20, 0, 21, 0, booking: true)], // starts when window ends
      requireActivityCode: 'PS5',
      compatibility: {'hex': GameAvailability.playable},
    );
    expect(ids(available), ['hex']);
  });

  test('player requirement beyond the game max → no systems', () {
    final available = svc.availableSystems(
      window: window,
      resources: resources,
      occupancies: const [],
      requireActivityCode: 'PS5',
      compatibility: playableEverywhere,
      gameMaxLocalPlayers: 2,
      playersRequired: 4,
    );
    expect(available, isEmpty);
  });

  group('specific system (spec §20B, §21)', () {
    test('rejects an incompatible game with a clear reason', () {
      final r = svc.checkSpecific(
        resource: res('rift', 'RIFT', acts: ['PS5', 'VR']),
        window: window,
        occupancies: const [],
        requireActivityCode: 'PS5',
        gameName: 'Tekken',
        compatibility: {'rift': GameAvailability.notPlayable},
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, 'Tekken is not playable on RIFT.');
    });

    test('rejects an occupied system with a clear reason', () {
      final r = svc.checkSpecific(
        resource: res('rift', 'RIFT', acts: ['PS5', 'VR']),
        window: window,
        occupancies: [occ('rift', 19, 30, 20, 30)],
        requireActivityCode: 'PS5',
        gameName: 'EA FC',
        compatibility: {'rift': GameAvailability.playable},
      );
      expect(r.isErr, isTrue);
      expect(r.failureOrNull!.message, 'RIFT is occupied during the requested time.');
    });

    test('accepts a compatible, free, operational system', () {
      final r = svc.checkSpecific(
        resource: res('void', 'VOID'),
        window: window,
        occupancies: const [],
        requireActivityCode: 'PS5',
        compatibility: {'void': GameAvailability.playable},
      );
      expect(r.isOk, isTrue);
    });
  });
}
