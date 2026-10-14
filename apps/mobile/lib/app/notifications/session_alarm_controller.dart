import 'dart:async';

import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/notifications/alarm_sound_service.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State of an active, foreground in-app session alarm.
@immutable
class ActiveAlarmState {
  const ActiveAlarmState({
    required this.sessionId,
    required this.stationName,
    required this.customerName,
    required this.slot,
    required this.title,
    required this.body,
    required this.scheduledEndAt,
    this.isSilenced = false,
    required this.triggeredAt,
  });

  /// Single session or group session id.
  final String sessionId;

  /// Station or resource label (e.g. 'HEX', 'BAY 1').
  final String stationName;

  /// Customer or group leader label.
  final String customerName;

  /// Alert slot: 0 = 5 min before, 1 = 1 min before, 2 = session time completed.
  final int slot;

  /// Prominent title, e.g. "HEX — Session time completed".
  final String title;

  /// Supporting detail, e.g. "Alex • Session time has ended (07:30 PM)".
  final String body;

  /// The scheduled deadline when this alert was evaluated.
  final DateTime scheduledEndAt;

  /// Whether staff has tapped "Silence" to stop audio while keeping the banner.
  final bool isSilenced;

  /// When this alarm started firing.
  final DateTime triggeredAt;

  bool get isEndingSoon => slot == 0 || slot == 1;
  bool get isCompleted => slot == 2;

  ActiveAlarmState copyWith({
    String? sessionId,
    String? stationName,
    String? customerName,
    int? slot,
    String? title,
    String? body,
    DateTime? scheduledEndAt,
    bool? isSilenced,
    DateTime? triggeredAt,
  }) =>
      ActiveAlarmState(
        sessionId: sessionId ?? this.sessionId,
        stationName: stationName ?? this.stationName,
        customerName: customerName ?? this.customerName,
        slot: slot ?? this.slot,
        title: title ?? this.title,
        body: body ?? this.body,
        scheduledEndAt: scheduledEndAt ?? this.scheduledEndAt,
        isSilenced: isSilenced ?? this.isSilenced,
        triggeredAt: triggeredAt ?? this.triggeredAt,
      );

  @override
  bool operator ==(Object other) =>
      other is ActiveAlarmState &&
      other.sessionId == sessionId &&
      other.stationName == stationName &&
      other.slot == slot &&
      other.scheduledEndAt == scheduledEndAt &&
      other.isSilenced == isSilenced;

  @override
  int get hashCode => Object.hash(sessionId, stationName, slot, scheduledEndAt, isSilenced);
}

/// Foreground coordinator that monitors running sessions, triggers audible
/// ring/alarm and provides in-app silence and dismiss actions.
class SessionAlarmController extends Notifier<ActiveAlarmState?>
    with WidgetsBindingObserver {
  final Set<String> _dismissedKeys = <String>{};
  Timer? _soundLoop;
  DateTime? _soundLoopStarted;

  @override
  ActiveAlarmState? build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _stopSound();
    });

    // Listen to 1-second ticker to reconcile deadlines in the foreground.
    ref.listen<AsyncValue<DateTime>>(nowProvider, (prev, next) {
      final now = next.value;
      if (now != null) {
        _onTick(now);
      }
    });

    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // In background, let the OS local notifications handle sound/banner.
      _stopSound();
    }
  }

  /// Evaluates active sessions against current clock time.
  void _onTick(DateTime now) {
    // Only fire foreground alarms when app is resumed/active.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
        WidgetsBinding.instance.lifecycleState != null) {
      return;
    }

    final settings = ref.read(notificationSettingsProvider).value ??
        const NotificationSettings();

    // 1. Check if current active alarm needs to auto-silence or cancel.
    if (state != null) {
      final current = state!;
      // Auto-silence ring after configured alarmDurationSeconds.
      if (!current.isSilenced && _soundLoopStarted != null) {
        final elapsed = now.difference(_soundLoopStarted!).inSeconds;
        if (elapsed >= settings.alarmDurationSeconds) {
          _stopSound();
          state = current.copyWith(isSilenced: true);
        }
      }

      // Check if session has ended, extended, or changed.
      final activeSessions = ref.read(activeSessionsProvider).value ?? [];
      final activeGroups = ref.read(activeGroupsProvider).value ?? [];

      final activeSingle = activeSessions.firstWhereOrNull(
          (a) => a.session.id == current.sessionId && a.session.isActive);
      final activeGroup = activeGroups.firstWhereOrNull((g) =>
          g.group.id == current.sessionId &&
          g.group.status == GroupSessionStatus.active);

      final currentEnd =
          activeSingle?.session.scheduledEndAt ?? activeGroup?.group.scheduledEndAt;

      // If session no longer running or scheduledEndAt was moved, dismiss alarm.
      if (currentEnd == null ||
          currentEnd.toUtc() != current.scheduledEndAt.toUtc()) {
        _stopSound();
        state = null;
      }
    }

    // 2. Scan active sessions for pending alerts.
    final activeSessions = ref.read(activeSessionsProvider).value ?? [];
    final activeGroups = ref.read(activeGroupsProvider).value ?? [];

    for (final running in activeSessions) {
      if (!running.session.isActive) continue;
      _evaluateCandidate(
        sessionId: running.session.id,
        resourceId: running.current.resourceId,
        customerId: running.session.customerId,
        scheduledEndAt: running.session.scheduledEndAt,
        isGroup: false,
        playerCount: 1,
        now: now,
        settings: settings,
      );
      if (state != null && !state!.isSilenced) return;
    }

    for (final g in activeGroups) {
      if (g.group.status != GroupSessionStatus.active) continue;
      _evaluateCandidate(
        sessionId: g.group.id,
        resourceId: null,
        customerId: g.group.primaryCustomerId,
        scheduledEndAt: g.group.scheduledEndAt,
        isGroup: true,
        playerCount: g.group.playerCount,
        now: now,
        settings: settings,
      );
      if (state != null && !state!.isSilenced) return;
    }
  }

  void _evaluateCandidate({
    required String sessionId,
    required String? resourceId,
    required String customerId,
    required DateTime scheduledEndAt,
    required bool isGroup,
    required int playerCount,
    required DateTime now,
    required NotificationSettings settings,
  }) {
    final endUtc = scheduledEndAt.toUtc();
    final nowUtc = now.toUtc();
    final secondsUntilEnd = endUtc.difference(nowUtc).inSeconds;

    // Check slots from highest priority (Slot 2 = completed) to lowest.
    // Slot 2: Session time completed (at or shortly after scheduled end, within 60s)
    if (settings.alertAtEnd &&
        secondsUntilEnd <= 0 &&
        secondsUntilEnd >= -60) {
      _triggerAlertIfNew(
        sessionId: sessionId,
        slot: 2,
        resourceId: resourceId,
        customerId: customerId,
        scheduledEndAt: scheduledEndAt,
        isGroup: isGroup,
        playerCount: playerCount,
        now: now,
        settings: settings,
      );
      return;
    }

    // Slot 1: 1 min before scheduled end (within window 50s..70s before end)
    if (settings.alert1Min &&
        secondsUntilEnd > 0 &&
        secondsUntilEnd <= 60 &&
        secondsUntilEnd >= 0) {
      _triggerAlertIfNew(
        sessionId: sessionId,
        slot: 1,
        resourceId: resourceId,
        customerId: customerId,
        scheduledEndAt: scheduledEndAt,
        isGroup: isGroup,
        playerCount: playerCount,
        now: now,
        settings: settings,
      );
      return;
    }

    // Slot 0: 5 min before scheduled end (within window 290s..310s before end)
    if (settings.alert5Min &&
        secondsUntilEnd > 60 &&
        secondsUntilEnd <= 300 &&
        secondsUntilEnd >= 240) {
      _triggerAlertIfNew(
        sessionId: sessionId,
        slot: 0,
        resourceId: resourceId,
        customerId: customerId,
        scheduledEndAt: scheduledEndAt,
        isGroup: isGroup,
        playerCount: playerCount,
        now: now,
        settings: settings,
      );
      return;
    }
  }

  Future<void> _triggerAlertIfNew({
    required String sessionId,
    required int slot,
    required String? resourceId,
    required String customerId,
    required DateTime scheduledEndAt,
    required bool isGroup,
    required int playerCount,
    required DateTime now,
    required NotificationSettings settings,
  }) async {
    final dismissalKey =
        '${sessionId}_${slot}_${scheduledEndAt.toUtc().toIso8601String()}';
    if (_dismissedKeys.contains(dismissalKey)) return;

    // If an alarm of higher or equal priority is already displaying for this session, don't replace.
    if (state != null && state!.sessionId == sessionId && state!.slot >= slot) {
      return;
    }

    // Resolve station and customer names.
    final catalog = ref.read(catalogRepositoryProvider);
    final customers = ref.read(customerRepositoryProvider);

    String stationName = 'Station';
    if (isGroup) {
      stationName = 'Group ($playerCount players)';
    } else if (resourceId != null) {
      try {
        final resources = await catalog.resources();
        stationName =
            resources.firstWhereOrNull((r) => r.id == resourceId)?.name ?? 'Station';
      } catch (_) {
        stationName = 'Station';
      }
    }

    String customerName = isGroup ? 'Group' : 'Guest';
    try {
      final customer = await customers.getById(customerId);
      if (customer != null && customer.name.isNotEmpty) {
        customerName = customer.name;
      }
    } catch (_) {}
    final endLabel = IstTime.format12(scheduledEndAt);

    final String title;
    final String body;

    switch (slot) {
      case 0:
        title = '$stationName — Ending soon (5m)';
        body = '$customerName • Ends at $endLabel. Prepare to extend or wrap up.';
        break;
      case 1:
        title = '$stationName — Ending soon (1m)';
        body = '$customerName • Ends in 1 minute ($endLabel)! Final reminder.';
        break;
      case 2:
      default:
        title = '$stationName — Session time completed';
        body = '$customerName • Session time has ended ($endLabel). Ready for checkout.';
        break;
    }

    state = ActiveAlarmState(
      sessionId: sessionId,
      stationName: stationName,
      customerName: customerName,
      slot: slot,
      title: title,
      body: body,
      scheduledEndAt: scheduledEndAt,
      isSilenced: false,
      triggeredAt: now,
    );

    _startSound(settings);
  }

  void _startSound(NotificationSettings settings) {
    _stopSound();
    _soundLoopStarted = DateTime.now();

    // Play immediately on trigger using physical device alarm stream.
    if (settings.soundEnabled) {
      AlarmSoundService.playAlarm();
    }
    if (settings.vibrationEnabled) {
      HapticFeedback.heavyImpact();
    }

    // Post an instant notification to show foreground heads-up banner and notification chime.
    if (state != null) {
      final plan = ReminderPlan(
        id: sessionAlertId(state!.sessionId, state!.slot),
        sessionId: state!.sessionId,
        fireAtUtc: DateTime.now(),
        title: state!.title,
        body: state!.body,
        enableVibration: settings.vibrationEnabled,
        playSound: settings.soundEnabled,
      );
      ref.read(notificationServiceProvider).showInstant(plan);
    }

    // Repeating loop every 2 seconds until silenced, dismissed, or timed out.
    _soundLoop = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (state == null || state!.isSilenced) {
        _stopSound();
        return;
      }
      if (settings.soundEnabled) {
        AlarmSoundService.playAlarm();
      }
      if (settings.vibrationEnabled) {
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _stopSound() {
    _soundLoop?.cancel();
    _soundLoop = null;
    _soundLoopStarted = null;
    AlarmSoundService.stopAlarm();
  }

  /// Silences the audible ring and vibration immediately, leaving the visible banner.
  void silence() {
    _stopSound();
    if (state != null) {
      state = state!.copyWith(isSilenced: true);
    }
  }

  /// Dismisses the alarm banner, silences audio, and marks this event acknowledged.
  void dismiss() {
    _stopSound();
    if (state != null) {
      final key =
          '${state!.sessionId}_${state!.slot}_${state!.scheduledEndAt.toUtc().toIso8601String()}';
      _dismissedKeys.add(key);
      state = null;
    }
  }

  /// Fires a quick test alert to verify audible chime and visual banner.
  void testAlarm() {
    final now = DateTime.now();
    final settings = ref.read(notificationSettingsProvider).value ??
        const NotificationSettings();

    state = ActiveAlarmState(
      sessionId: 'test_session',
      stationName: 'TEST STATION',
      customerName: 'Test Customer',
      slot: 2,
      title: 'TEST STATION — Session time completed',
      body: 'Test Customer • Audible alarm & notification test.',
      scheduledEndAt: now,
      isSilenced: false,
      triggeredAt: now,
    );

    _startSound(settings);
  }
}

final sessionAlarmControllerProvider =
    NotifierProvider<SessionAlarmController, ActiveAlarmState?>(
  SessionAlarmController.new,
);
