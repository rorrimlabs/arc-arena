import 'dart:io';

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/services/pad_selection.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pricing_fixtures.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late FakeClock clock;
  late AppDatabase db;
  late ProviderContainer container;

  final startTime = ist(2026, 10, 2, 18, 0);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('arena_ops_timer_test');
    dbFile = File('${tempDir.path}/test.sqlite');
    clock = FakeClock(startTime);
    db = AppDatabase(NativeDatabase(dbFile));
    await LocalSeed.applyIfEmpty(db);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        authControllerProvider.overrideWith(
          () => _TestAuthController(
            AppUser(
              id: 'usr_owner',
              name: 'Owner',
              perms: {
                Permission.start,
                Permission.bill,
                Permission.discount,
                Permission.settings,
              },
            ),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'Gaming timer start, live elapsed progression, and restoration',
    () async {
      final actions = container.read(sessionActionsProvider);

      // 1. Start session on PS5
      final startRes = await actions.start(
        NewSessionDraft(
          customerId: 'cust_walkin',
          activityCode: 'PS5',
          resourceId: 'hex',
          resourceName: 'Station 1 (Hex)',
          durationMinutes: 60,
          controllers: ControllerChoice.count(1),
        ),
      );
      expect(startRes.isOk, isTrue);
      final session = startRes.valueOrNull!;
      expect(session.startedAt, startTime);
      expect(session.scheduledEndAt, startTime.add(const Duration(hours: 1)));
      expect(session.actualEndedAt, isNull);

      // 2. Check initial timer state
      var timer = SessionTimer(
        startedAt: session.startedAt,
        scheduledEndAt: session.scheduledEndAt,
      );
      expect(timer.elapsed(clock.now()), Duration.zero);
      expect(timer.remaining(clock.now()), const Duration(hours: 1));
      expect(timer.state(clock.now()), SessionVisualState.normal);

      // 3. Advance clock by 25 minutes
      clock.advance(const Duration(minutes: 25));
      expect(timer.elapsed(clock.now()), const Duration(minutes: 25));
      expect(timer.remaining(clock.now()), const Duration(minutes: 35));

      // 4. Timer restoration from fresh DB read (simulating restart or backgrounding)
      final repo = container.read(sessionRepositoryProvider);
      final activeList = await repo.active();
      expect(activeList.length, 1);
      final restoredSession = activeList.first.session;
      final restoredTimer = SessionTimer(
        startedAt: restoredSession.startedAt,
        scheduledEndAt: restoredSession.scheduledEndAt,
      );
      expect(restoredTimer.elapsed(clock.now()), const Duration(minutes: 25));
      expect(restoredTimer.remaining(clock.now()), const Duration(minutes: 35));
    },
  );

  test('Switching stations during an active session preserves timing and calculates correct bill', () async {
    final actions = container.read(sessionActionsProvider);
    final repo = container.read(sessionRepositoryProvider);

    // Start on hex for 60 min with 1 controller
    final startRes = await actions.start(
      NewSessionDraft(
        customerId: 'cust_walkin',
        activityCode: 'PS5',
        resourceId: 'hex',
        resourceName: 'Station 1 (Hex)',
        durationMinutes: 60,
        controllers: ControllerChoice.count(1),
      ),
    );
    expect(startRes.isOk, isTrue);
    final session = startRes.valueOrNull!;

    // Play 30 minutes on hex
    clock.advance(const Duration(minutes: 30));

    var active = (await repo.active()).first;
    expect(active.segments.length, 1);
    expect(active.current.resourceId, 'hex');

    // Switch to void
    final switchRes = await actions.switchSystem(
      session: session,
      current: active.current,
      resourceId: 'void',
      resourceName: 'VOID',
      activityCode: 'PS5',
      controllerCount: 1,
    );
    expect(switchRes.isOk, isTrue);

    // Verify segments: segment 1 ended at 30 min, segment 2 started at 30 min
    active = (await repo.active()).first;
    expect(active.segments.length, 2);
    expect(active.segments[0].resourceId, 'hex');
    expect(
      active.segments[0].endedAt,
      startTime.add(const Duration(minutes: 30)),
    );
    expect(active.segments[1].resourceId, 'void');
    expect(
      active.segments[1].startedAt,
      startTime.add(const Duration(minutes: 30)),
    );
    expect(active.segments[1].isOpen, isTrue);

    // Parent session startedAt is completely untouched
    expect(active.session.startedAt, startTime);

    // Play another 30 minutes on void
    clock.advance(const Duration(minutes: 30));

    // End session at 60 minutes
    final endRes = await actions.end(active.session, active.segments);
    expect(endRes.isOk, isTrue);
    final endedSession = endRes.valueOrNull!;
    expect(endedSession.actualEndedAt, startTime.add(const Duration(hours: 1)));

    // Billed amount must match exactly 1 hour of PS5 (15000 paise)
    expect(endedSession.billedAmountPaise, 15000);
  });

  test(
    'Switching controllers during an active session re-prices accurately',
    () async {
      final actions = container.read(sessionActionsProvider);
      final repo = container.read(sessionRepositoryProvider);

      // Start on hex with 1 controller
      final startRes = await actions.start(
        NewSessionDraft(
          customerId: 'cust_walkin',
          activityCode: 'PS5',
          resourceId: 'hex',
          resourceName: 'Station 1 (Hex)',
          durationMinutes: 60,
          controllers: ControllerChoice.count(1),
        ),
      );
      final session = startRes.valueOrNull!;

      // Play 30 minutes with 1 controller
      clock.advance(const Duration(minutes: 30));

      var active = (await repo.active()).first;
      // Add second player / controller
      final changeRes = await actions.changeControllers(
        session: session,
        current: active.current,
        controllerCount: 2,
      );
      expect(changeRes.isOk, isTrue);

      // Play another 30 minutes with 2 controllers
      clock.advance(const Duration(minutes: 30));

      active = (await repo.active()).first;
      expect(active.segments.length, 2);

      // End session
      final endRes = await actions.end(active.session, active.segments);
      expect(endRes.isOk, isTrue);
      final ended = endRes.valueOrNull!;

      // Segment 1 (30m @ 1 ctrl = 150/2 = 75.00)
      // Segment 2 (30m @ 2 ctrl = 280/2 = 140.00)
      // Total = 215.00 (21500 paise)
      expect(ended.billedAmountPaise, 21500);
    },
  );

  test('Pool table session timer and billing without controllers', () async {
    final actions = container.read(sessionActionsProvider);
    final repo = container.read(sessionRepositoryProvider);

    // Start pool session on pool1
    final startRes = await actions.start(
      NewSessionDraft(
        customerId: 'cust_walkin',
        activityCode: 'POOL',
        resourceId: 'pool1',
        resourceName: 'Pool Table 1',
        durationMinutes: 60,
        controllers: ControllerChoice.none,
      ),
    );
    expect(startRes.isOk, isTrue);
    final session = startRes.valueOrNull!;
    expect(session.startedAt, startTime);

    // Advance 60 minutes
    clock.advance(const Duration(minutes: 60));

    final active = (await repo.active()).first;
    expect(active.current.resourceId, 'pool1');
    expect(active.current.controllerCount, isNull);

    // End session
    final endRes = await actions.end(active.session, active.segments);
    expect(endRes.isOk, isTrue);
    final ended = endRes.valueOrNull!;

    // Standard POOL hourly rate is 27500 paise
    expect(ended.billedAmountPaise, 27500);
  });

  test('VR session timer and billing on unit model', () async {
    final actions = container.read(sessionActionsProvider);
    final repo = container.read(sessionRepositoryProvider);

    // Start VR session on rift
    final startRes = await actions.start(
      NewSessionDraft(
        customerId: 'cust_walkin',
        activityCode: 'VR',
        resourceId: 'rift',
        resourceName: 'RIFT (VR)',
        durationMinutes: 30,
        controllers: ControllerChoice.none,
      ),
    );
    expect(startRes.isOk, isTrue);
    final session = startRes.valueOrNull!;
    expect(session.startedAt, startTime);

    // Advance 30 minutes
    clock.advance(const Duration(minutes: 30));

    final active = (await repo.active()).first;
    expect(active.current.resourceId, 'rift');

    // End session
    final endRes = await actions.end(active.session, active.segments);
    expect(endRes.isOk, isTrue);
    final ended = endRes.valueOrNull!;

    // Standard VR 30-min unit rate is 20000 paise
    expect(ended.billedAmountPaise, 20000);
  });
}

class _TestAuthController extends AuthController {
  _TestAuthController(this._user);
  final AppUser _user;

  @override
  AppUser? build() => _user;
}
