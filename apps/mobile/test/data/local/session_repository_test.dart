import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/services/segment_billing.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  late AppDatabase db;
  late LocalSessionRepository sessions;
  late LocalCatalogRepository catalog;
  late LocalCustomerRepository customers;
  late PricingSnapshot snapshot;
  late Customer rahul;

  const billing = SegmentBilling();
  final start = ist(2026, 10, 2, 18, 0);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    sessions = LocalSessionRepository(db);
    catalog = LocalCatalogRepository(db);
    customers = LocalCustomerRepository(db);
    snapshot = await catalog.currentSnapshot();
    rahul = await customers.create(name: 'Rahul', phone: '9000000001');
  });

  tearDown(() async => db.close());

  StartSessionCommand startCmd(
    String resourceId,
    String resourceName,
    String activity,
    int? controllers, {
    String? gameId,
    int durationMin = 60,
  }) =>
      StartSessionCommand(
        customerId: rahul.id,
        startedAt: start,
        scheduledEndAt: start.add(Duration(minutes: durationMin)),
        snapshot: snapshot,
        resourceId: resourceId,
        resourceName: resourceName,
        activityCode: activity,
        gameId: gameId,
        controllerCount: controllers,
      );

  group('catalog + compatibility (spec §4)', () {
    test('seed loaded', () async {
      expect((await catalog.activities()).length, 4);
      expect((await catalog.resources()).length, 6);
      expect((await catalog.games(activeOnly: true)).length, 16);
    });

    test('compatibility matches the spec examples', () async {
      expect(await catalog.availabilityOf('g_eafc', 'hex'), GameAvailability.playable);
      expect(await catalog.availabilityOf('g_eafc', 'ghost'), GameAvailability.notPlayable);
      expect(await catalog.availabilityOf('g_tekken8', 'rift'), GameAvailability.notPlayable);
      expect(await catalog.availabilityOf('g_gtav', 'hex'), GameAvailability.notPlayable);
      // Absent row → not installed (never globally available).
      expect(await catalog.availabilityOf('g_beatsaber', 'hex'), GameAvailability.notInstalled);
    });
  });

  group('start + occupancy (spec §24)', () {
    test('start creates a parent with one open segment', () async {
      final r = await sessions.start(startCmd('hex', 'HEX', 'PS5', 2));
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      final active = await sessions.active();
      expect(active.length, 1);
      expect(active.single.segments.length, 1);
      expect(active.single.current.resourceId, 'hex');
      expect((await sessions.openSegments()).length, 1);
    });

    test('overlapping start on the same resource is rejected', () async {
      await sessions.start(startCmd('hex', 'HEX', 'PS5', 2));
      final second = await sessions.start(startCmd('hex', 'HEX', 'PS5', 1));
      expect(second.failureOrNull?.code, 'resource_busy');
    });

    test('RIFT: a PS5 session blocks a VR start (spec §25)', () async {
      await sessions.start(startCmd('rift', 'RIFT', 'PS5', 1));
      final vr = await sessions.start(startCmd('rift', 'RIFT', 'VR', null, durationMin: 30));
      expect(vr.failureOrNull?.code, 'resource_busy');
    });
  });

  group('switch system (spec §10)', () {
    test('closes one segment and opens the next at the same instant', () async {
      final s = (await sessions.start(startCmd('hex', 'HEX', 'PS5', 2))).valueOrNull!;
      final at = start.add(const Duration(minutes: 30));
      final r = await sessions.reconfigure(ReconfigureCommand(
        sessionId: s.id, at: at, resourceId: 'void', resourceName: 'VOID',
        activityCode: 'PS5', controllerCount: 2,
      ));
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);

      final segs = await sessions.segmentsFor(s.id);
      expect(segs.length, 2);
      expect(segs[0].endedAt, at); // closed exactly at the switch
      expect(segs[1].startedAt, at); // opened exactly at the switch — no gap/overlap
      expect(segs[1].resourceId, 'void');
      expect(segs[1].isOpen, isTrue);

      // HEX is now free; VOID is occupied.
      final open = await sessions.openSegments();
      expect(open.single.resourceId, 'void');
    });

    test('switching to an occupied system is rejected', () async {
      final s = (await sessions.start(startCmd('hex', 'HEX', 'PS5', 2))).valueOrNull!;
      await sessions.start(startCmd('void', 'VOID', 'PS5', 1)); // void now busy
      final r = await sessions.reconfigure(ReconfigureCommand(
        sessionId: s.id, at: start.add(const Duration(minutes: 10)),
        resourceId: 'void', resourceName: 'VOID', activityCode: 'PS5', controllerCount: 2,
      ));
      expect(r.failureOrNull?.code, 'resource_busy');
    });
  });

  group('change controllers (spec §12)', () {
    test('creates a new segment with the new count', () async {
      final s = (await sessions.start(startCmd('hex', 'HEX', 'PS5', 2))).valueOrNull!;
      final at = start.add(const Duration(minutes: 30));
      await sessions.reconfigure(ReconfigureCommand(
        sessionId: s.id, at: at, resourceId: 'hex', resourceName: 'HEX',
        activityCode: 'PS5', controllerCount: 1,
      ));
      final segs = await sessions.segmentsFor(s.id);
      expect(segs.length, 2);
      expect(segs[0].controllerCount, 2);
      expect(segs[1].controllerCount, 1);
      expect(segs[1].resourceId, 'hex');
    });
  });

  group('billing follows segments (spec §14)', () {
    Future<void> endWith(String id, List<dynamic> segs, DateTime at) async {
      final bill = billing.bill(
        snapshot: snapshot,
        segments: await sessions.segmentsFor(id),
        openEndAt: at,
      );
      await sessions.end(EndSessionCommand(
        sessionId: id,
        actualEndedAt: at,
        charges: bill.charges,
        billedAmountPaise: bill.total.value,
      ));
    }

    test('switching system with the same config bills like one session (₹280)', () async {
      final s = (await sessions.start(startCmd('hex', 'HEX', 'PS5', 2))).valueOrNull!;
      await sessions.reconfigure(ReconfigureCommand(
        sessionId: s.id, at: start.add(const Duration(minutes: 30)),
        resourceId: 'void', resourceName: 'VOID', activityCode: 'PS5', controllerCount: 2,
      ));
      await endWith(s.id, [], start.add(const Duration(minutes: 60)));
      final ended = (await sessions.getById(s.id))!;
      expect(ended.status, SessionStatus.completed);
      expect(ended.billedAmountPaise, 28000); // 60 min PS5 2c
      expect((await sessions.chargesFor(s.id)).length, 2); // one per segment
    });

    test('controller change bills each segment correctly (2c 30m + 1c 30m = ₹215)', () async {
      final s = (await sessions.start(startCmd('hex', 'HEX', 'PS5', 2))).valueOrNull!;
      await sessions.reconfigure(ReconfigureCommand(
        sessionId: s.id, at: start.add(const Duration(minutes: 30)),
        resourceId: 'hex', resourceName: 'HEX', activityCode: 'PS5', controllerCount: 1,
      ));
      await endWith(s.id, [], start.add(const Duration(minutes: 60)));
      expect((await sessions.getById(s.id))!.billedAmountPaise, 21500);
    });

    test('ending twice writes charges once (idempotent)', () async {
      final s = (await sessions.start(startCmd('hex', 'HEX', 'PS5', 1))).valueOrNull!;
      await endWith(s.id, [], start.add(const Duration(minutes: 60)));
      await endWith(s.id, [], start.add(const Duration(minutes: 60)));
      expect((await sessions.chargesFor(s.id)).length, 1);
      expect((await sessions.active()).length, 0);
    });
  });
}
