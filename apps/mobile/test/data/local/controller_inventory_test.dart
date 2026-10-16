/// Step 1 of the controller-allocation plan: the physical inventory exists and
/// is readable. No allocation logic yet — these tests pin the data only, so a
/// later step cannot quietly change what "usable at this station" means.
library;

import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/entities/controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  late AppDatabase db;
  late LocalCatalogRepository catalog;

  final at = ist(2026, 10, 6, 18, 0);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    catalog = LocalCatalogRepository(db, FakeClock(at));
  });

  tearDown(() async => db.close());

  /// Usable pads physically present at a station — the supply side of
  /// allocation, before anything committed to a session is subtracted.
  Future<int> usableAt(String resourceId) async => (await catalog.controllers())
      .where((c) => c.currentResourceId == resourceId && c.status.isUsable)
      .length;

  group('the seeded floor', () {
    test('has eight controllers, two per PS5 station', () async {
      final all = await catalog.controllers();
      expect(all.length, 8);

      for (final station in const ['hex', 'void', 'ghost', 'rift']) {
        expect(await usableAt(station), 2, reason: station);
      }
      // Pool and the lounge use no controllers at all.
      expect(await usableAt('pool1'), 0);
      expect(await usableAt('lounge1'), 0);
    });

    test('every pad starts at home, usable, and carries its physical label',
        () async {
      for (final c in await catalog.controllers()) {
        expect(c.status, ControllerStatus.usable);
        expect(c.currentResourceId, c.homeResourceId);
        expect(c.isAwayFromHome, isFalse);
        expect(c.isOnLoan, isFalse);
      }
      expect(
        (await catalog.controllers()).map((c) => c.label),
        containsAll(<String>['HEX-1', 'HEX-2', 'VOID-1', 'RIFT-2']),
      );
    });
  });

  group('marking a pad', () {
    test('faulty removes it from the usable supply but keeps the row',
        () async {
      await catalog.setControllerStatus(
        'ctl_hex_2',
        ControllerStatus.faulty,
        notes: 'left stick drift',
      );

      expect(await usableAt('hex'), 1, reason: 'HEX is down to one');
      // The pad is still on the books — a shortfall must stay visible.
      final hex2 =
          (await catalog.controllers()).firstWhere((c) => c.id == 'ctl_hex_2');
      expect(hex2.status, ControllerStatus.faulty);
      expect(hex2.notes, 'left stick drift');
      expect((await catalog.controllers()).length, 8);
    });

    test('missing and retired are also excluded from the usable supply',
        () async {
      await catalog.setControllerStatus('ctl_void_1', ControllerStatus.missing);
      await catalog.setControllerStatus('ctl_void_2', ControllerStatus.retired);
      expect(await usableAt('void'), 0);
    });

    test('repairing it puts the pad back', () async {
      await catalog.setControllerStatus('ctl_hex_2', ControllerStatus.faulty);
      expect(await usableAt('hex'), 1);

      await catalog.setControllerStatus('ctl_hex_2', ControllerStatus.usable);
      expect(await usableAt('hex'), 2);
    });
  });

  group('moving a pad', () {
    test('a loan changes where it is, never where it belongs', () async {
      final ghost1 = (await catalog.controllers())
          .firstWhere((c) => c.id == 'ctl_ghost_1');

      await catalog.upsertController(ghost1.copyWith(
        currentResourceId: 'hex',
        loanReturnTo: 'ghost',
        loanSessionRef: Controller.sessionRef('sess-1'),
      ));

      expect(await usableAt('hex'), 3, reason: 'HEX can now seat three');
      expect(await usableAt('ghost'), 1, reason: 'GHOST gave one up');

      final moved = (await catalog.controllers())
          .firstWhere((c) => c.id == 'ctl_ghost_1');
      expect(moved.homeResourceId, 'ghost', reason: 'home is unchanged');
      expect(moved.isAwayFromHome, isTrue);
      expect(moved.isOnLoan, isTrue);
      expect(moved.loanReturnTo, 'ghost');
    });

    test('a permanent move re-homes it and owes no return', () async {
      final ghost1 = (await catalog.controllers())
          .firstWhere((c) => c.id == 'ctl_ghost_1');

      await catalog.upsertController(ghost1.copyWith(
        homeResourceId: 'hex',
        currentResourceId: 'hex',
      ));

      final moved = (await catalog.controllers())
          .firstWhere((c) => c.id == 'ctl_ghost_1');
      expect(moved.homeResourceId, 'hex');
      expect(moved.isAwayFromHome, isFalse);
      expect(moved.isOnLoan, isFalse, reason: 'nothing to unwind at checkout');
      expect(await usableAt('hex'), 3);
      expect(await usableAt('ghost'), 1);
    });

    test('the whole floor still has eight pads after a move', () async {
      final ghost1 = (await catalog.controllers())
          .firstWhere((c) => c.id == 'ctl_ghost_1');
      await catalog.upsertController(ghost1.copyWith(currentResourceId: 'hex'));

      final total = (await catalog.controllers())
          .where((c) => c.status.isUsable)
          .length;
      expect(total, 8, reason: 'moving a pad never creates or destroys one');
    });
  });

  test('the inventory stream reports a fault without a refetch', () async {
    final seen = <int>[];
    final sub = catalog.watchControllers().listen((all) => seen.add(all
        .where((c) => c.currentResourceId == 'hex' && c.status.isUsable)
        .length));
    // Let the first emission land before changing anything.
    await pumpEventQueue();

    await catalog.setControllerStatus('ctl_hex_1', ControllerStatus.faulty);
    await pumpEventQueue();
    await sub.cancel();

    expect(seen.first, 2, reason: 'HEX started whole');
    expect(seen.last, 1, reason: 'and the fault arrived on the stream');
  });
}
