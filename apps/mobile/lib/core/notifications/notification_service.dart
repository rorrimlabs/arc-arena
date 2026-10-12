/// Device-local notification scheduling (spec §23, §32). Thin wrapper over
/// `flutter_local_notifications` so the rest of the app depends on a small
/// interface it can fake in tests.
///
/// Scheduling is handed to the OS, so a booking reminder fires at the right time
/// **with no network** — and survives the app being closed. The payloads come
/// from the pure `buildBookingReminders` builder; this layer only talks to the
/// platform.
library;

import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

abstract interface class NotificationService {
  /// Initialise the platform plugin and the timezone database. Safe to call
  /// more than once.
  Future<void> init();

  /// Ask the OS for permission to post notifications. Returns whether granted.
  Future<bool> requestPermission();

  /// Schedule one notification. Re-scheduling the same [ReminderPlan.id]
  /// replaces the previous one (no duplicates).
  Future<void> schedule(ReminderPlan plan);

  /// Show an immediate notification now (e.g. for testing alerts).
  Future<void> showInstant(ReminderPlan plan);

  /// Cancel a single scheduled notification by id.
  Future<void> cancel(int id);

  /// Cancel every scheduled notification (used to reconcile on startup).
  Future<void> cancelAll();
}

/// A no-op service for tests and platforms without notification support. Never
/// throws, so booking flows behave identically whether or not notifications are
/// available.
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(ReminderPlan plan) async {}
  @override
  Future<void> showInstant(ReminderPlan plan) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
}

/// Real implementation backed by `flutter_local_notifications`.
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const bookingChannelId = 'booking_reminders';
  static const bookingChannelName = 'Booking reminders';
  static const bookingChannelDescription =
      'Reminders before a booked session starts.';

  static const sessionChannelVibrateId = 'session_alerts_vibrate';
  static const sessionChannelVibrateName = 'Session Timer Alerts (Vibrate)';
  static const sessionChannelVibrateDesc =
      'Alerts for session timers with vibration (5m, 1m, and expired).';

  static const sessionChannelNoVibrateId = 'session_alerts_no_vibrate';
  static const sessionChannelNoVibrateName = 'Session Timer Alerts (Sound Only)';
  static const sessionChannelNoVibrateDesc =
      'Alerts for session timers with sound only (5m, 1m, and expired).';

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          bookingChannelId,
          bookingChannelName,
          description: bookingChannelDescription,
          importance: Importance.max,
          playSound: true,
        ),
      );
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          sessionChannelVibrateId,
          sessionChannelVibrateName,
          description: sessionChannelVibrateDesc,
          importance: Importance.max,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
          playSound: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          sessionChannelNoVibrateId,
          sessionChannelNoVibrateName,
          description: sessionChannelNoVibrateDesc,
          importance: Importance.max,
          enableVibration: false,
          playSound: true,
        ),
      );
    }

    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  NotificationDetails _detailsFor(ReminderPlan plan) {
    final bool isSession = plan.sessionId != null || plan.channelId != null;
    final String channelId = plan.channelId ??
        (isSession
            ? (plan.enableVibration
                ? sessionChannelVibrateId
                : sessionChannelNoVibrateId)
            : bookingChannelId);

    final String channelName = isSession
        ? (plan.enableVibration
            ? sessionChannelVibrateName
            : sessionChannelNoVibrateName)
        : bookingChannelName;

    final String channelDesc = isSession
        ? (plan.enableVibration
            ? sessionChannelVibrateDesc
            : sessionChannelNoVibrateDesc)
        : bookingChannelDescription;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: plan.playSound,
        enableVibration: plan.enableVibration,
        vibrationPattern: plan.enableVibration
            ? Int64List.fromList([0, 500, 250, 500])
            : null,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: plan.playSound,
      ),
    );
  }

  @override
  Future<void> schedule(ReminderPlan plan) async {
    await init();
    final when = tz.TZDateTime.from(plan.fireAtUtc.toUtc(), tz.UTC);
    try {
      await _plugin.zonedSchedule(
        plan.id,
        plan.title,
        plan.body,
        when,
        _detailsFor(plan),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: plan.bookingId.isNotEmpty ? plan.bookingId : plan.sessionId,
      );
    } catch (e) {
      debugPrint('notification schedule failed: $e');
    }
  }

  @override
  Future<void> showInstant(ReminderPlan plan) async {
    await init();
    try {
      if (plan.enableVibration) {
        HapticFeedback.vibrate();
      }
      await _plugin.show(
        plan.id,
        plan.title,
        plan.body,
        _detailsFor(plan),
        payload: plan.bookingId.isNotEmpty ? plan.bookingId : plan.sessionId,
      );
    } catch (e) {
      debugPrint('instant notification failed: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('notification cancel failed: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    await init();
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('notification cancelAll failed: $e');
    }
  }
}
