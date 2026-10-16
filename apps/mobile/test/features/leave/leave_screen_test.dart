import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/leave_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/attendance_failures.dart';
import 'package:arena_ops/data/remote/leave_failures.dart';
import 'package:arena_ops/data/remote/unavailable_leave_repository.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:arena_ops/domain/repositories/leave_repository.dart';
import 'package:arena_ops/features/leave/presentation/leave_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_leave.dart';
import '../../support/pricing_fixtures.dart' show ist;
import '../../support/test_db.dart' show TestStaffAuth;

void main() {
  // Friday 16 Oct 2026, 10:00 AM IST.
  final now = ist(2026, 10, 16, 10, 0);
  late FakeLeaveRepository repo;

  setUp(() => repo = FakeLeaveRepository(now: () => now));

  Widget app({LeaveRepository? repository}) => ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(TestStaffAuth.new),
          clockProvider.overrideWithValue(FakeClock(now)),
          leaveRepositoryProvider.overrideWithValue(repository ?? repo),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const LeaveScreen()),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  LeaveRequest approved() => LeaveRequest(
        id: 'r-approved',
        kind: LeaveKind.planned,
        from: const IstDate(2026, 10, 5),
        to: const IstDate(2026, 10, 7),
        days: 3,
        paidDays: 2,
        lopDays: 1,
        reason: 'sister wedding',
        status: LeaveStatus.approved,
        decisionNote: 'enjoy',
        createdAt: now,
      );

  for (final (name, size) in [('phone', phone), ('desktop', desktop)]) {
    testWidgets('$name: balance, requests and the paid / LOP split', (tester) async {
      size(tester);
      repo.requests.add(approved());
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.text('8 days of 12 days'), findsOneWidget);
      expect(find.textContaining('Leave year 1 Jun 2026 – 31 May 2027'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.text('3 days · Planned · 2 days paid · 1 day LOP'), findsOneWidget);
      await tester.tap(find.text('Mon 5 Oct – Wed 7 Oct'));
      await settle(tester);
      expect(find.textContaining('2 days paid from your balance, 1 day loss of pay'), findsOneWidget);
      expect(find.text('enjoy'), findsOneWidget);
      await tester.tap(find.text('Ask to cancel this leave'));
      await settle(tester);
      expect(repo.cancelled, ['r-approved']);
      expect(find.textContaining('Cancellation sent'), findsOneWidget);
      expect(find.text('Cancel requested'), findsOneWidget);
    });
  }

  testWidgets('apply: reason, send, and it shows as waiting', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.text('No leave requests yet.'), findsOneWidget);
    await tester.tap(find.text('Apply for leave'));
    await settle(tester);
    expect(find.text('From Fri 16 Oct'), findsOneWidget);
    expect(find.textContaining('You have 8 paid days left'), findsOneWidget);
    await tester.tap(find.text('Unplanned'));
    await tester.tap(find.text('Second half'));
    await tester.enterText(find.byType(TextField), 'Doctor visit');
    await tester.tap(find.text('Send request'));
    await settle(tester);
    final sent = repo.sent.single;
    expect([sent.kind, sent.halfDay, sent.reason],
        [LeaveKind.unplanned, HalfDay.secondHalf, 'Doctor visit']);
    expect(find.textContaining('Leave requested: 0.5 working days'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
  });

  testWidgets('a refusal shows the server words; offline offers Try again with the same id',
      (tester) async {
    desktop(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.tap(find.text('Apply for leave'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'trip');
    repo.nextFailure = LeaveFailures.rejected('no_working_days', null);
    await tester.tap(find.text('Send request'));
    await settle(tester);
    expect(find.text('You are not scheduled to work on those days.'), findsOneWidget);
    repo.nextFailure = AttendanceFailures.offline;
    await tester.tap(find.text('Send request'));
    await settle(tester);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(repo.sent, hasLength(3));
    expect(repo.sent[2].id, repo.sent[1].id);
    expect(find.text('Waiting'), findsOneWidget);
  });

  testWidgets('without the online arena it says so', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(repository: const UnavailableLeaveRepository()));
    await settle(tester);
    expect(find.text(LeaveFailures.cloudOnly.message), findsOneWidget);
    expect(find.text('Apply for leave'), findsNothing);
  });
}
