/// Device-local notification scheduling (spec §23, §32). Thin wrapper over
/// `flutter_local_notifications` so the rest of the app depends on a small
/// interface it can fake in tests.
///
/// Scheduling is handed to the OS, so a booking reminder fires at the right time
/// **with no network** — and survives the app being closed. The payloads come
/// from the pure `buildBookingReminders` / `buildSessionAlerts` builders and
/// how each rings from the pure [alertStyleFor]; this layer only talks to the
/// platform.
library;

import 'package:arena_ops/core/notifications/alert_channels.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

abstract interface class NotificationService {
  /// Initialise the platform plugin. Safe to call more than once.
  Future<void> init();

  /// Ask the OS for permission to post notifications. Returns whether granted.
  Future<bool> requestPermission();

  /// Whether the phone lets this app show notifications now; null when the
  /// platform does not say.
  Future<bool?> notificationsAllowed();

  /// Whether Android lets this app ring at the exact minute ("Alarms &
  /// reminders"); off, alerts may come a few minutes late. Null on iOS, where
  /// it does not apply.
  Future<bool?> exactAlarmsAllowed();

  /// Opens Android's "Alarms & reminders" page for this app. Returns whether
  /// exact alarms are allowed afterwards.
  Future<bool> requestExactAlarms();

  /// Opens this app's notification settings in the phone's Settings, for a
  /// permission that can no longer be asked for. Returns whether it opened.
  Future<bool> openSystemSettings();

  /// Schedule one notification. Re-scheduling the same [ReminderPlan.id]
  /// replaces the previous one (no duplicates).
  Future<void> schedule(ReminderPlan plan);

  /// Show an immediate notification now (e.g. for testing alerts).
  Future<void> showInstant(ReminderPlan plan);

  /// Cancel a single scheduled notification by id.
  Future<void> cancel(int id);

  /// Cancel every scheduled (not yet shown) notification (leaving an arena).
  /// Notifications already delivered stay in the tray: a time-up alert that
  /// fired while the app was closed must still be there when it opens.
  Future<void> cancelAll();

  /// Ids of the notifications scheduled and not yet shown — what an earlier
  /// run left behind, for the start-up sweep.
  Future<List<int>> pendingIds();
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
  Future<bool?> notificationsAllowed() async => null;
  @override
  Future<bool?> exactAlarmsAllowed() async => null;
  @override
  Future<bool> requestExactAlarms() async => false;
  @override
  Future<bool> openSystemSettings() async => false;
  @override
  Future<void> schedule(ReminderPlan plan) async {}
  @override
  Future<void> showInstant(ReminderPlan plan) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<List<int>> pendingIds() async => const [];
}

/// Real implementation backed by `flutter_local_notifications`.
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// MainActivity.kt: opens this app's notification settings on Android.
  static const _systemSettings = MethodChannel('arena_ops/system_settings');

  @override
  Future<void> init() async {
    if (_ready) return;
    // No timezone database: alerts are scheduled in tz.UTC, which the package
    // has built in. Decoding the full IANA database here ran synchronously on
    // the UI isolate — on iOS the main thread — at every start.
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);

    final android = _android;
    if (android != null) {
      for (final channel in AlertChannels.all) {
        await android.createNotificationChannel(_androidChannel(channel));
      }
      for (final id in AlertChannels.obsoleteIds) {
        await android.deleteNotificationChannel(id);
      }
    }

    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// Sound and vibration are fixed when a channel is first created, so each
  /// [AlertChannel] is created exactly as it must ring.
  static AndroidNotificationChannel _androidChannel(AlertChannel c) =>
      AndroidNotificationChannel(
        c.id,
        c.name,
        description: c.description,
        importance: Importance.max,
        playSound: c.sound,
        enableVibration: c.vibrate,
        vibrationPattern: c.vibrate ? Int64List.fromList(c.pattern) : null,
        audioAttributesUsage: c.alarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
      );

  @override
  Future<bool> requestPermission() async {
    try {
      await init();
      final ios = _ios;
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('notification permission request failed: $e');
      return false;
    }
  }

  @override
  Future<bool?> notificationsAllowed() async {
    try {
      await init();
      final ios = _ios;
      if (ios != null) return (await ios.checkPermissions())?.isEnabled;
      return await _android?.areNotificationsEnabled();
    } catch (e) {
      debugPrint('notification permission check failed: $e');
      return null;
    }
  }

  @override
  Future<bool?> exactAlarmsAllowed() async {
    try {
      await init();
      return await _android?.canScheduleExactNotifications();
    } catch (e) {
      debugPrint('exact alarm check failed: $e');
      return null;
    }
  }

  @override
  Future<bool> requestExactAlarms() async {
    try {
      await init();
      return await _android?.requestExactAlarmsPermission() ?? false;
    } catch (e) {
      debugPrint('exact alarm request failed: $e');
      return false;
    }
  }

  @override
  Future<bool> openSystemSettings() async {
    try {
      return switch (defaultTargetPlatform) {
        // This app's page in Settings; Notifications is its first row.
        TargetPlatform.iOS => await launchUrl(Uri.parse('app-settings:')),
        TargetPlatform.android =>
          await _systemSettings.invokeMethod<bool>(
                'openNotificationSettings',
              ) ??
              false,
        _ => false,
      };
    } catch (e) {
      debugPrint('opening notification settings failed: $e');
      return false;
    }
  }

  NotificationDetails _detailsFor(ReminderPlan plan) {
    final style = alertStyleFor(plan);
    final c = style.channel;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: Importance.max,
        priority: style.alarm ? Priority.max : Priority.high,
        // Android 7 and older read these from the notification itself.
        playSound: c.sound,
        enableVibration: c.vibrate,
        vibrationPattern: c.vibrate ? Int64List.fromList(c.pattern) : null,
        audioAttributesUsage: c.alarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
        category: style.alarm ? AndroidNotificationCategory.alarm : null,
        visibility: style.alarm ? NotificationVisibility.public : null,
        additionalFlags: style.insistent
            ? Int32List.fromList(const [androidFlagInsistent])
            : null,
      ),
      // Shown and heard with the app open too (AppDelegate sets the
      // notification centre delegate).
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentBadge: true,
        presentSound: c.sound,
      ),
    );
  }

  @override
  Future<void> schedule(ReminderPlan plan) async {
    try {
      await init();
    } catch (e) {
      debugPrint('notification schedule failed: $e');
      return;
    }
    final when = tz.TZDateTime.from(plan.fireAtUtc.toUtc(), tz.UTC);
    Future<void> zoned(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      plan.id,
      plan.title,
      plan.body,
      when,
      _detailsFor(plan),
      androidScheduleMode: mode,
      payload: plan.bookingId.isNotEmpty ? plan.bookingId : plan.sessionId,
    );
    try {
      await zoned(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') {
        debugPrint('notification schedule failed: $e');
        return;
      }
      // Android 12+ can refuse exact alarms ("Alarms & reminders" off): an
      // alert that may come a little late beats no alert at all.
      try {
        await zoned(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e2) {
        debugPrint('notification schedule failed: $e2');
      }
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
      // Scheduled ones only: delivered alerts stay in the tray.
      await _plugin.cancelAllPendingNotifications();
    } catch (e) {
      debugPrint('notification cancelAll failed: $e');
    }
  }

  @override
  Future<List<int>> pendingIds() async {
    await init();
    try {
      return [
        for (final p in await _plugin.pendingNotificationRequests()) p.id,
      ];
    } catch (e) {
      debugPrint('notification pending list failed: $e');
      return const [];
    }
  }
}
