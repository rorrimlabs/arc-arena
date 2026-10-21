import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/services/group_billing.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  const billing = GroupBilling();
  final snapshot = currentSnapshot();
  // Friday 18:00 IST — standard band throughout.
  final start = ist(2026, 10, 2, 18, 0);
  final end60 = start.add(const Duration(minutes: 60));

  GroupAssignment ga(
    int player,
    String resource, {
    String game = 'g_wwe',
    int? controllers = 1,
    DateTime? from,
    DateTime? to,
  }) =>
      GroupAssignment(
        id: 'a${player}_$resource',
        groupId: 'g',
        playerNumber: player,
        index: 0,
        resourceId: resource,
        activityCode: 'PS5',
        gameId: game,
        controllerCount: controllers,
        startedAt: from ?? start,
        endedAt: to,
        createdAt: from ?? start,
      );

  GroupBill bill(List<GroupAssignment> a, GroupBillingMode mode,
          {int purchased = 3}) =>
      billing.bill(
        snapshot: snapshot,
        assignments: a,
        mode: mode,
        purchasedControllerCount: purchased,
        groupStart: start,
        openEndAt: end60,
      );

  group('per-system', () {
    test('three players on one system → the 3-controller rate (₹390)', () {
      final b = bill(
        [ga(1, 'hex'), ga(2, 'hex'), ga(3, 'hex')],
        GroupBillingMode.perSystem,
      );
      expect(b.total.value, 39000);
    });

    test('three players on three systems → 3 × the 1-controller rate (₹450)',
        () {
      final b = bill(
        [ga(1, 'hex'), ga(2, 'void'), ga(3, 'ghost')],
        GroupBillingMode.perSystem,
      );
      expect(b.total.value, 45000);
    });

    test('a mid-session switch bills each stretch (30m + 30m @1c = ₹150)', () {
      final mid = start.add(const Duration(minutes: 30));
      final b = bill(
        [
          ga(1, 'hex', to: mid), // closed first stretch
          ga(1, 'void', from: mid), // open second stretch (to end60)
        ],
        GroupBillingMode.perSystem,
      );
      expect(b.total.value, 15000);
    });

    test('controllers combine only while players overlap on a system', () {
      final mid = start.add(const Duration(minutes: 30));
      // P1 on HEX the whole hour; P2 joins HEX for the second half.
      final b = bill(
        [ga(1, 'hex'), ga(2, 'hex', from: mid)],
        GroupBillingMode.perSystem,
      );
      // 0–30: 1c (₹75) ; 30–60: 2c (₹280/h → ₹140). Total ₹215.
      expect(b.total.value, 7500 + 14000);
    });
  });

  group('shared controller pool', () {
    test('three systems but purchased controllers billed once (₹390)', () {
      final b = bill(
        [ga(1, 'hex'), ga(2, 'void'), ga(3, 'ghost')],
        GroupBillingMode.sharedControllerPool,
      );
      expect(b.total.value, 39000);
    });
  });
}
