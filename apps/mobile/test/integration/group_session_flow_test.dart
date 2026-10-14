import 'package:arena_ops/app/controllers/group_session_actions.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_group_session_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/domain/entities/resource.dart';
import 'package:arena_ops/domain/entities/booking.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pricing_fixtures.dart';

/// End-to-end through the application controller: build a group from a draft,
/// switch a player, extend, and bill — the way the UI drives it.
void main() {
  late AppDatabase db;
  late GroupSessionActions actions;
  late LocalGroupSessionRepository groups;
  late Customer rahul;

  final start = ist(2026, 10, 2, 18, 0);
  final clock = FakeClock(start);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    groups = LocalGroupSessionRepository(db, clock);
    final catalog = LocalCatalogRepository(db);
    final sessions = LocalSessionRepository(db, clock);
    final customers = LocalCustomerRepository(db, clock);
    rahul = await customers.create(name: 'Rahul', phone: '9000000002');
    actions = GroupSessionActions(
      groups: groups,
      sessions: sessions,
      catalog: catalog,
      bookings: LocalBookingRepository(db, clock),
      clock: clock,
      // The real app passes the signed-in user; without one every action is
      // refused, which is what `test/app/permissions_test.dart` covers.
      guard: const PermissionGuard(AppUser(
        id: 'u2',
        name: 'Priya Nair',
        perms: {
          Permission.start,
          Permission.bill,
          Permission.discount,
          Permission.members,
        },
      )),
    );
  });

  tearDown(() async => db.close());

  GroupSessionDraft draft() => GroupSessionDraft(
        primaryCustomerId: rahul.id,
        playerCount: 3,
        purchasedControllerCount: 3,
        durationMinutes: 60,
        players: [
          GroupPlayerDraft(
              playerNumber: 1,
              resourceId: 'hex',
              resourceName: 'HEX',
              activityCode: 'PS5',
              gameId: 'g_wwe',
              controllerCount: 1),
          GroupPlayerDraft(
              playerNumber: 2,
              resourceId: 'void',
              resourceName: 'VOID',
              activityCode: 'PS5',
              gameId: 'g_wwe',
              controllerCount: 1),
          GroupPlayerDraft(
              playerNumber: 3,
              resourceId: 'ghost',
              resourceName: 'GHOST',
              activityCode: 'PS5',
              gameId: 'g_wwe',
              controllerCount: 1),
        ],
      );

  test('a reservation on a station keeps a group off it', () async {
    // HEX is reserved from 6:30 PM; the group wants it from 6:00 for an hour.
    final now = clock.now();
    await LocalBookingRepository(db, clock).create(Booking(
      id: 'bk-1',
      activityCode: 'PS5',
      resourceId: 'hex',
      scheduledStart: now.add(const Duration(minutes: 30)),
      scheduledEnd: now.add(const Duration(minutes: 90)),
      status: BookingStatus.booked,
      partyName: 'Nikhil',
      createdAt: now,
      updatedAt: now,
    ));

    final r = await actions.create(draft());
    expect(r.isErr, isTrue,
        reason: 'a group spread over a reservation double-books it just as a '
            'walk-in would');
    expect(await groups.openAssignments(), isEmpty);
  });

  test('a station in maintenance cannot take a group player', () async {
    await LocalCatalogRepository(db)
        .setResourceStatus('hex', ResourceStatus.maintenance);
    final r = await actions.create(draft());
    expect(r.isErr, isTrue);
    expect(r.failureOrNull!.code, 'resource_unavailable');
    expect(await groups.openAssignments(), isEmpty);
  });

  test('preview estimates the per-system total (₹450)', () async {
    final preview = await actions.previewCreate(draft());
    expect(preview.isOk, isTrue, reason: preview.failureOrNull?.display);
    expect(preview.valueOrNull!.estimate.value, 45000);
  });

  test('create → switch → extend → bill keeps one shared countdown', () async {
    final created = await actions.create(draft());
    expect(created.isOk, isTrue, reason: created.failureOrNull?.display);
    final group = created.valueOrNull!;
    final end0 = group.scheduledEndAt;

    // A free, compatible system is offered for a switch.
    final candidates = await actions.candidateResources(
      group: group,
      playerNumber: 1,
      activityCode: 'PS5',
      gameId: 'g_wwe',
      controllerCount: 1,
    );
    expect(candidates.any((r) => r.id == 'rift'), isTrue);

    final switched = await actions.switchSystem(
      groupId: group.id,
      playerNumber: 1,
      resourceId: 'rift',
      resourceName: 'RIFT',
      activityCode: 'PS5',
      gameId: 'g_wwe',
      controllerCount: 1,
    );
    expect(switched.isOk, isTrue, reason: switched.failureOrNull?.display);

    // The shared end did not move on the switch (group feature §3).
    expect((await groups.getById(group.id))!.scheduledEndAt, end0);

    // Extend the whole group by 30 minutes.
    final active = (await groups.activeGroups()).single;
    final extended = await actions.extend(active, 30);
    expect(extended.isOk, isTrue, reason: extended.failureOrNull?.display);
    expect((await groups.getById(group.id))!.scheduledEndAt,
        end0.add(const Duration(minutes: 30)));

    // Bill at the scheduled end: still three single-controller systems → ₹450.
    final atEnd = end0.add(const Duration(minutes: 30));
    final toEnd = (await groups.activeGroups()).single;
    final ended = await actions.end(toEnd, at: atEnd);
    expect(ended.isOk, isTrue, reason: ended.failureOrNull?.display);
    // 90 minutes now: 3 systems × ₹150/h × 1.5h = ₹675.
    expect(ended.valueOrNull!.billedAmountPaise, 67500);

    // The timer is derived purely from the stored window.
    final timer = SessionTimer(
      startedAt: ended.valueOrNull!.startedAt,
      scheduledEndAt: ended.valueOrNull!.scheduledEndAt,
      actualEndedAt: ended.valueOrNull!.actualEndedAt,
    );
    expect(timer.remaining(atEnd), Duration.zero);
  });

  test('a group waive needs a reason; with one the group ends waived', () async {
    final created = await actions.create(draft());
    expect(created.isOk, isTrue, reason: created.failureOrNull?.display);
    clock.advance(const Duration(hours: 1));
    final active = (await groups.activeGroups()).single;

    final refused = await actions.end(active, markWaived: true, waiveReason: ' ');
    expect(refused.failureOrNull?.code, 'waive_reason_required');
    expect((await groups.activeGroups()), hasLength(1),
        reason: 'the group keeps running');

    final waived =
        await actions.end(active, markWaived: true, waiveReason: 'Tournament prize');
    expect(waived.isOk, isTrue, reason: waived.failureOrNull?.display);
    expect(waived.valueOrNull!.paymentStatus, PaymentStatus.waived);
  });
}
