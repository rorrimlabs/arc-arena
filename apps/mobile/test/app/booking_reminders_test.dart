import 'package:arena_ops/app/controllers/booking_actions.dart';
import 'package:arena_ops/app/notifications/booking_reminders.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/notifications/notification_service.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_booking_repository.dart';
import 'package:arena_ops/data/local/local_catalog_repository.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/local_session_repository.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_db.dart';

/// Records what the app asks the OS to schedule/cancel, so we can assert the
/// booking lifecycle drives reminders correctly — without any platform channel.
class _RecordingService implements NotificationService {
  final List<ReminderPlan> scheduled = [];
  final List<int> cancelled = [];
  int cancelAllCount = 0;

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> schedule(ReminderPlan plan) async => scheduled.add(plan);
  @override
  Future<void> showInstant(ReminderPlan plan) async => scheduled.add(plan);
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
  @override
  Future<void> cancelAll() async => cancelAllCount++;
}

void main() {
  late AppDatabase db;
  late _RecordingService service;
  late BookingActions actions;
  late BookingReminders reminders;
  late LocalBookingRepository bookingsRepo;
  late String customerId;

  // Mon 2026-10-06 00:00 UTC — the booking is later the same IST day.
  final clock = FakeClock(DateTime.utc(2026, 10, 6, 0, 0));

  setUp(() async {
    db = await seededMemoryDb();
    service = _RecordingService();
    final catalog = LocalCatalogRepository(db);
    final customers = LocalCustomerRepository(db, clock);
    bookingsRepo = LocalBookingRepository(db, clock);
    final sessions = LocalSessionRepository(db, clock);
    reminders = BookingReminders(
      service: service,
      bookings: bookingsRepo,
      customers: customers,
      catalog: catalog,
      clock: clock,
    );
    actions = BookingActions(
      bookings: bookingsRepo,
      sessions: sessions,
      catalog: catalog,
      clock: clock,
      guard: const PermissionGuard(AppUser(
        id: 'u2',
        name: 'Staff',
        perms: {Permission.start},
      )),
      reminders: reminders,
    );
    final rahul = await customers.create(name: 'Rahul', phone: '9000000001');
    customerId = rahul.id;
  });
  tearDown(() async => db.close());

  BookingDraft draft() => BookingDraft(
        customerId: customerId,
        activityCode: 'PS5',
        date: IstDate(2026, 10, 6),
        startMinuteOfDay: 15 * 60, // 3:00 PM IST
        durationMinutes: 60,
        gameId: 'g_eafc',
        resourceId: 'void',
      );

  test('creating a booking schedules a 30-min reminder (spec §23)', () async {
    final result = await actions.createBooking(draft());
    expect(result.isOk, isTrue);

    expect(service.scheduled, hasLength(1));
    final plan = service.scheduled.single;
    // 3:00 PM IST == 09:30 UTC; reminder fires 30 min earlier.
    expect(plan.fireAtUtc, DateTime.utc(2026, 10, 6, 9, 0));
    expect(plan.body, contains('Rahul'));
    expect(plan.body, contains('3:00 PM'));
    expect(plan.body, contains('VOID'));
  });

  test('cancelling a booking cancels its reminders', () async {
    final created = (await actions.createBooking(draft())).valueOrNull!;
    service.cancelled.clear();

    await actions.cancel(created.id);

    expect(service.cancelled, contains(reminderId(created.id, 0)));
    expect(service.cancelled, contains(reminderId(created.id, 1)));
  });

  test('syncUpcoming clears all then reschedules booked future bookings', () async {
    await actions.createBooking(draft());
    service.scheduled.clear();

    await reminders.syncUpcoming();

    // Cancels everything first (de-dupe on restart), then reschedules the one.
    expect(service.cancelAllCount, 1);
    expect(service.scheduled, hasLength(1));
  });
}
