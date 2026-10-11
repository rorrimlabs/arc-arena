import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  test('Customer JSON round-trips', () {
    final c = Customer(
      id: 'c1',
      name: 'Rahul',
      phone: '9999999999',
      createdAt: DateTime.utc(2026, 10, 2, 10),
      updatedAt: DateTime.utc(2026, 10, 2, 10),
    );
    expect(Customer.fromJson(c.toJson()), c);
  });

  test('Session decodes its immutable pricing snapshot (spec §31)', () {
    final snap = currentSnapshot();
    final session = Session(
      id: 's1',
      customerId: 'c1',
      status: SessionStatus.active,
      paymentStatus: PaymentStatus.unpaid,
      startedAt: DateTime.utc(2026, 10, 2, 12, 30),
      scheduledEndAt: DateTime.utc(2026, 10, 2, 13, 30),
      pricingSnapshot: snap.toJson(),
      createdAt: DateTime.utc(2026, 10, 2, 12, 30),
      updatedAt: DateTime.utc(2026, 10, 2, 12, 30),
    );
    final decoded = session.snapshot;
    expect(decoded.rateCardName, 'Current');
    expect(
      decoded.rateFor(activityCode: 'PS5', band: Band.standard, controllerCount: 2)!.price.value,
      28000,
    );
    expect(session.isActive, isTrue);
  });

  test('ActiveSession.current is the open segment', () {
    SessionSegment seg(int i, DateTime start, DateTime? end) => SessionSegment(
          id: 'seg$i',
          sessionId: 's1',
          index: i,
          resourceId: i == 0 ? 'hex' : 'void',
          activityCode: 'PS5',
          startedAt: start,
          endedAt: end,
          createdAt: start,
        );
    final t0 = DateTime.utc(2026, 10, 2, 12, 0);
    final t1 = DateTime.utc(2026, 10, 2, 12, 40);
    final active = ActiveSession(
      session: Session(
        id: 's1',
        customerId: 'c1',
        status: SessionStatus.active,
        paymentStatus: PaymentStatus.unpaid,
        startedAt: t0,
        scheduledEndAt: DateTime.utc(2026, 10, 2, 13, 30),
        pricingSnapshot: currentSnapshot().toJson(),
        createdAt: t0,
        updatedAt: t0,
      ),
      segments: [seg(0, t0, t1), seg(1, t1, null)],
    );
    expect(active.current.resourceId, 'void');
    expect(active.current.isOpen, isTrue);
  });
}
