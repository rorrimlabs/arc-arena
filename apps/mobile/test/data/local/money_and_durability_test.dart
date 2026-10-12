/// Brief §16 — the money and durability guarantees that are easy to claim and
/// hard to keep:
///
///   #14 price changes do not alter historical bills
///   #15 partial and split payments produce the correct balance
///   #16 retried operations do not duplicate sessions, segments or payments
///   #17 records survive a reload (the local database is the source of truth)
///   #18 checkout releases resources and preserves payment history
library;

import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/pricing/pricing_snapshot.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/repositories/commands.dart';
import 'package:arena_ops/domain/services/segment_billing.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'dart:io';

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
  // Friday 6 PM — outside happy hour, so one clean standard hour.
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

  Future<String> startHex({int durationMin = 60, int controllers = 1}) async {
    final r = await sessions.start(StartSessionCommand(
      customerId: rahul.id,
      startedAt: start,
      scheduledEndAt: start.add(Duration(minutes: durationMin)),
      snapshot: snapshot,
      resourceId: 'hex',
      resourceName: 'HEX',
      activityCode: 'PS5',
      gameId: 'g_eafc', // a real seeded game: 'g_fifa' never existed
      controllerCount: controllers,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return r.valueOrNull!.id;
  }

  Future<int> endAndBill(String id, {DateTime? at}) async {
    final end = at ?? start.add(const Duration(hours: 1));
    final segs = await sessions.segmentsFor(id);
    final session = (await sessions.getById(id))!;
    final bill = billing.bill(
      snapshot: session.snapshot,
      segments: segs,
      openEndAt: end,
    );
    final r = await sessions.end(EndSessionCommand(
      sessionId: id,
      actualEndedAt: end,
      charges: bill.charges,
      billedAmountPaise: bill.total.value,
    ));
    expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    return bill.total.value;
  }

  group('#14 price changes never alter a historical bill', () {
    test('re-pricing an old session uses the snapshot it started with', () async {
      final id = await startHex();
      final billed = await endAndBill(id);
      expect(billed, 15000, reason: '1 controller, one standard hour = ₹150');

      // The owner puts the 1-controller rate up to ₹200 afterwards.
      await catalog.upsertRate(const Rate(
        activityCode: 'PS5',
        band: Band.standard,
        controllerCount: 1,
        unitMinutes: 60,
        price: Paise(20000),
      ));
      final newSnapshot = await catalog.currentSnapshot();
      expect(
        newSnapshot
            .rateFor(
                activityCode: 'PS5', band: Band.standard, controllerCount: 1)!
            .price,
        const Paise(20000),
        reason: 'the live rate card did change',
      );

      // The stored bill is untouched…
      final stored = (await sessions.getById(id))!;
      expect(stored.billedAmountPaise, 15000);

      // …and so is the charge row behind it.
      final charges = await sessions.chargesFor(id);
      expect(charges.single.amountPaise, 15000);
      expect(charges.single.unitPricePaise, 15000);

      // …and re-running the billing from the session's own snapshot still
      // produces the old price, not the new one.
      final segs = await sessions.segmentsFor(id);
      final rebilled = billing.bill(
        snapshot: stored.snapshot,
        segments: segs,
        openEndAt: start.add(const Duration(hours: 1)),
      );
      expect(rebilled.total.value, 15000);

      // A session started now does pick up the new price.
      final next = await sessions.start(StartSessionCommand(
        customerId: rahul.id,
        startedAt: start.add(const Duration(hours: 2)),
        scheduledEndAt: start.add(const Duration(hours: 3)),
        snapshot: newSnapshot,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      final nextBill = billing.bill(
        snapshot: next.valueOrNull!.snapshot,
        segments: await sessions.segmentsFor(next.valueOrNull!.id),
        openEndAt: start.add(const Duration(hours: 3)),
      );
      expect(nextBill.total.value, 20000);
    });
  });

  group('#15 partial and split payments', () {
    test('₹200 UPI + ₹80 cash settles a ₹280 bill exactly', () async {
      final id = await startHex(controllers: 2);
      final billed = await endAndBill(id);
      expect(billed, 28000, reason: '2 controllers for an hour = ₹280');

      await sessions.recordPayment(RecordPaymentCommand(
        sessionId: id,
        amountPaise: 20000,
        method: PaymentMethod.upi,
      ));
      var session = (await sessions.getById(id))!;
      expect(session.paymentStatus, PaymentStatus.partial);

      final afterFirst = await sessions.paymentsFor(id);
      expect(afterFirst.fold<int>(0, (a, p) => a + p.amountPaise), 20000);

      await sessions.recordPayment(RecordPaymentCommand(
        sessionId: id,
        amountPaise: 8000,
        method: PaymentMethod.cash,
      ));
      session = (await sessions.getById(id))!;
      expect(session.paymentStatus, PaymentStatus.paid);

      // Two separate transactions, each keeping its own method — the first is
      // never overwritten.
      final all = await sessions.paymentsFor(id);
      expect(all.length, 2);
      expect(all.map((p) => p.method),
          containsAll([PaymentMethod.upi, PaymentMethod.cash]));
      expect(all.fold<int>(0, (a, p) => a + p.amountPaise), 28000);
      expect(billed - all.fold<int>(0, (a, p) => a + p.amountPaise), 0);
    });

    test('a refund is an extra row with a reason, not an edit', () async {
      final id = await startHex();
      await endAndBill(id);
      await sessions.recordPayment(RecordPaymentCommand(
        sessionId: id,
        amountPaise: 15000,
        method: PaymentMethod.cash,
      ));

      final noReason = await sessions.recordPayment(RecordPaymentCommand(
        sessionId: id,
        amountPaise: -5000,
        method: PaymentMethod.cash,
        isRefund: true,
      ));
      expect(noReason.isErr, isTrue, reason: 'a refund must say why');

      await sessions.recordPayment(RecordPaymentCommand(
        sessionId: id,
        amountPaise: -5000,
        method: PaymentMethod.cash,
        isRefund: true,
        reason: 'Left 20 minutes early',
      ));

      final all = await sessions.paymentsFor(id);
      expect(all.length, 2, reason: 'the original payment is still there');
      expect(all.fold<int>(0, (a, p) => a + p.amountPaise), 10000);
      final refund = all.firstWhere((p) => p.isRefund);
      expect(refund.reason, 'Left 20 minutes early');

      final session = (await sessions.getById(id))!;
      expect(session.paymentStatus, PaymentStatus.partial,
          reason: '₹100 of a ₹150 bill is now settled');
    });
  });

  // Same rule as the server's op_payment (migration 0016).
  group('payments fit the bill', () {
    test('a settled bill cannot be collected twice; an advance counts '
        'toward the final bill', () async {
      final id = await startHex(controllers: 2);
      // Taken while the session ran: no final bill yet, so not capped.
      final advance = await sessions.recordPayment(RecordPaymentCommand(
          sessionId: id, amountPaise: 10000, method: PaymentMethod.cash));
      expect(advance.isOk, isTrue);
      final billed = await endAndBill(id);
      expect(billed, 28000);

      final tooMuch = await sessions.recordPayment(RecordPaymentCommand(
          sessionId: id, amountPaise: 28000, method: PaymentMethod.upi));
      expect(tooMuch.failureOrNull?.code, 'overpayment',
          reason: 'the ₹100 advance is already in the till');
      expect(tooMuch.failureOrNull?.message, contains('₹180'));

      final rest = await sessions.recordPayment(RecordPaymentCommand(
          sessionId: id, amountPaise: 18000, method: PaymentMethod.upi));
      expect(rest.isOk, isTrue);
      expect((await sessions.getById(id))!.paymentStatus, PaymentStatus.paid);

      final again = await sessions.recordPayment(RecordPaymentCommand(
          sessionId: id, amountPaise: 1, method: PaymentMethod.cash));
      expect(again.failureOrNull?.code, 'overpayment');
      final total = (await sessions.paymentsFor(id))
          .fold<int>(0, (a, p) => a + p.amountPaise);
      expect(total, billed, reason: 'collected exactly the bill');
    });

    test('a refund cannot give back more than was collected', () async {
      final id = await startHex();
      await endAndBill(id);
      await sessions.recordPayment(RecordPaymentCommand(
          sessionId: id, amountPaise: 5000, method: PaymentMethod.cash));
      final over = await sessions.recordPayment(RecordPaymentCommand(
          sessionId: id,
          amountPaise: 6000,
          method: PaymentMethod.cash,
          isRefund: true,
          reason: 'test'));
      expect(over.failureOrNull?.code, 'refund_exceeds_paid');
      expect(await sessions.paymentsFor(id), hasLength(1),
          reason: 'nothing was written');
    });
  });

  group('#16 retried operations do not duplicate', () {
    test('a repeated start on a busy station is refused, not duplicated',
        () async {
      await startHex();
      final retry = await sessions.start(StartSessionCommand(
        customerId: rahul.id,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(hours: 1)),
        snapshot: snapshot,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      expect(retry.isErr, isTrue);
      expect(retry.failureOrNull!.code, 'resource_busy');
      expect((await sessions.active()).length, 1);
      expect((await sessions.openSegments()).length, 1);
    });

    test('ending twice keeps one set of charges and one end time', () async {
      final id = await startHex();
      final first = await endAndBill(id);
      final chargesAfterFirst = await sessions.chargesFor(id);
      final endedAt = (await sessions.getById(id))!.actualEndedAt;

      // The same checkout, retried — e.g. the staff member tapped twice.
      final second = await sessions.end(EndSessionCommand(
        sessionId: id,
        actualEndedAt: start.add(const Duration(hours: 2)),
        charges: chargesAfterFirst,
        billedAmountPaise: 99900,
      ));
      expect(second.isOk, isTrue, reason: 'a retry is accepted, not an error');

      final after = await sessions.getById(id);
      expect(after!.billedAmountPaise, first,
          reason: 'the second call must not re-bill');
      expect(after.actualEndedAt, endedAt);
      expect((await sessions.chargesFor(id)).length, chargesAfterFirst.length);
    });

    test('a reconfigure replaces the open segment rather than adding one',
        () async {
      final id = await startHex();
      final at = start.add(const Duration(minutes: 30));
      await sessions.reconfigure(ReconfigureCommand(
        sessionId: id,
        at: at,
        resourceId: 'void',
        resourceName: 'VOID',
        activityCode: 'PS5',
        gameId: 'g_eafc', // a real seeded game: 'g_fifa' never existed
        controllerCount: 1,
      ));

      final segs = await sessions.segmentsFor(id);
      expect(segs.length, 2);
      expect(segs.where((s) => s.isOpen).length, 1,
          reason: 'exactly one segment is open at a time');
      // No gap and no overlap across the handover.
      expect(segs[0].endedAt, at);
      expect(segs[1].startedAt, at);
      // HEX is free again; VOID is now the busy one.
      final open = await sessions.openSegments();
      expect(open.single.resourceId, 'void');
    });
  });

  group('#17/#18 durability and checkout', () {
    test('sessions, segments and payments survive reopening the database',
        () async {
      // A file-backed database, so the data really leaves this process.
      final dir = await Directory.systemTemp.createTemp('arena_ops_reload');
      final file = File('${dir.path}/arena.sqlite');
      var disk = AppDatabase(NativeDatabase(file));
      await LocalSeed.apply(disk);
      var repo = LocalSessionRepository(disk);
      final catalogOnDisk = LocalCatalogRepository(disk);
      final customerOnDisk = LocalCustomerRepository(disk);
      final snap = await catalogOnDisk.currentSnapshot();
      final who = await customerOnDisk.create(name: 'Meera');

      final started = await repo.start(StartSessionCommand(
        customerId: who.id,
        startedAt: start,
        scheduledEndAt: start.add(const Duration(hours: 1)),
        snapshot: snap,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      final id = started.valueOrNull!.id;
      await repo.recordPayment(RecordPaymentCommand(
        sessionId: id,
        amountPaise: 5000,
        method: PaymentMethod.cash,
      ));
      await disk.close();

      // Reopen — as a restart, a crash recovery or a device reboot would.
      disk = AppDatabase(NativeDatabase(file));
      repo = LocalSessionRepository(disk);

      final reloaded = await repo.getById(id);
      expect(reloaded, isNotNull);
      // The timestamps are the authority, and they came back unchanged.
      expect(reloaded!.startedAt, start);
      expect(reloaded.scheduledEndAt, start.add(const Duration(hours: 1)));
      expect(reloaded.status, SessionStatus.active);
      expect((await repo.segmentsFor(id)).single.resourceId, 'hex');
      expect((await repo.paymentsFor(id)).single.amountPaise, 5000);
      // The station is still shown as occupied after the restart.
      expect((await repo.openSegments()).single.resourceId, 'hex');

      await disk.close();
      await dir.delete(recursive: true);
    });

    test('checkout frees the station and keeps every payment', () async {
      final id = await startHex();
      await sessions.recordPayment(RecordPaymentCommand(
        sessionId: id,
        amountPaise: 5000,
        method: PaymentMethod.upi,
        note: 'advance',
      ));

      expect((await sessions.openSegments()).length, 1);
      final billed = await endAndBill(id);

      // Resource released: nothing is open on it any more, and a new session
      // can take it immediately.
      expect(await sessions.openSegments(), isEmpty);
      final next = await sessions.start(StartSessionCommand(
        customerId: rahul.id,
        startedAt: start.add(const Duration(hours: 1)),
        scheduledEndAt: start.add(const Duration(hours: 2)),
        snapshot: snapshot,
        resourceId: 'hex',
        resourceName: 'HEX',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      expect(next.isOk, isTrue);

      // The advance payment taken before checkout is still on the record, and
      // the balance reflects it.
      final payments = await sessions.paymentsFor(id);
      expect(payments.single.amountPaise, 5000);
      expect(payments.single.note, 'advance');
      final session = (await sessions.getById(id))!;
      expect(session.paymentStatus, PaymentStatus.partial);
      expect(billed - 5000, session.billedAmountPaise! - 5000);
    });

    test('an unpaid finished session shows up in the pending queue', () async {
      final paidId = await startHex();
      await endAndBill(paidId);
      await sessions.recordPayment(RecordPaymentCommand(
        sessionId: paidId,
        amountPaise: 15000,
        method: PaymentMethod.cash,
      ));

      final owingId = await sessions.start(StartSessionCommand(
        customerId: rahul.id,
        startedAt: start.add(const Duration(hours: 2)),
        scheduledEndAt: start.add(const Duration(hours: 3)),
        snapshot: snapshot,
        resourceId: 'void',
        resourceName: 'VOID',
        activityCode: 'PS5',
        controllerCount: 1,
      ));
      await endAndBill(owingId.valueOrNull!.id,
          at: start.add(const Duration(hours: 3)));

      final pending = await sessions.watchAwaitingPayment().first;
      expect(pending.map((s) => s.id), [owingId.valueOrNull!.id]);
    });
  });
}

