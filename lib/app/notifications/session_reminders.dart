import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/notifications/notification_service.dart';
import 'package:arena_ops/domain/entities/group_session.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:arena_ops/domain/repositories/catalog_repository.dart';
import 'package:arena_ops/domain/repositories/customer_repository.dart';
import 'package:arena_ops/domain/repositories/group_session_repository.dart';
import 'package:arena_ops/domain/repositories/notification_settings_repository.dart';
import 'package:arena_ops/domain/repositories/session_repository.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Orchestrates session timer alerts (spec §23, timer alerts):
/// Schedules 5-minute lead, 1-minute lead ("1 min mune alert") and time expired ("സമയം കഴിഞ്ഞു").
/// Alerts work fully offline on the device without internet.
class SessionReminders {
  SessionReminders({
    required this.service,
    required this.sessions,
    required this.groups,
    required this.customers,
    required this.catalog,
    required this.settingsRepo,
    required this.clock,
  });

  final NotificationService service;
  final SessionRepository sessions;
  final GroupSessionRepository groups;
  final CustomerRepository customers;
  final CatalogRepository catalog;
  final NotificationSettingsRepository settingsRepo;
  final Clock clock;

  /// Schedule (or reschedule) timer alerts for one single session.
  Future<void> scheduleFor(Session session) async {
    if (session.status != SessionStatus.active) {
      await cancelFor(session.id);
      return;
    }
    try {
      final settings = await settingsRepo.getSettings();
      final customer = await customers.getById(session.customerId);
      final customerName = customer?.name ?? 'Guest';

      final active = await sessions.active();
      final currentSeg = active
          .firstWhereOrNull((a) => a.session.id == session.id)
          ?.current;
      String stationName = 'Station';
      if (currentSeg != null) {
        final resources = await catalog.resources();
        stationName = resources
                .firstWhereOrNull((r) => r.id == currentSeg.resourceId)
                ?.name ??
            'Station';
      }

      final label = '$stationName ($customerName)';
      final plans = buildSessionAlerts(
        sessionId: session.id,
        titleName: label,
        scheduledEndAt: session.scheduledEndAt,
        now: clock.now(),
        vibrationEnabled: settings.vibrationEnabled,
        soundEnabled: settings.soundEnabled,
        alert5Min: settings.alert5Min,
        alert1Min: settings.alert1Min,
        alertAtEnd: settings.alertAtEnd,
      );

      for (final plan in plans) {
        await service.schedule(plan);
      }
    } catch (e) {
      debugPrint('SessionReminders.scheduleFor(${session.id}) failed: $e');
    }
  }

  /// Schedule (or reschedule) timer alerts for one group session.
  Future<void> scheduleForGroup(GroupSession group) async {
    if (group.status != GroupSessionStatus.active) {
      await cancelFor(group.id);
      return;
    }
    try {
      final settings = await settingsRepo.getSettings();
      final customer = await customers.getById(group.primaryCustomerId);
      final customerName = customer?.name ?? 'Group';
      final label = 'Group (${group.playerCount}p) — $customerName';

      final plans = buildSessionAlerts(
        sessionId: group.id,
        titleName: label,
        scheduledEndAt: group.scheduledEndAt,
        now: clock.now(),
        vibrationEnabled: settings.vibrationEnabled,
        soundEnabled: settings.soundEnabled,
        alert5Min: settings.alert5Min,
        alert1Min: settings.alert1Min,
        alertAtEnd: settings.alertAtEnd,
      );

      for (final plan in plans) {
        await service.schedule(plan);
      }
    } catch (e) {
      debugPrint('SessionReminders.scheduleForGroup(${group.id}) failed: $e');
    }
  }

  /// Cancel all 3 alert slots for a session (on session end or void).
  Future<void> cancelFor(String sessionId) async {
    try {
      await service.cancel(sessionAlertId(sessionId, 0));
      await service.cancel(sessionAlertId(sessionId, 1));
      await service.cancel(sessionAlertId(sessionId, 2));
    } catch (e) {
      debugPrint('SessionReminders.cancelFor($sessionId) failed: $e');
    }
  }

  /// Reconcile alerts for all currently active single & group sessions.
  /// Called on startup and whenever settings change.
  Future<void> syncActive() async {
    try {
      final activeSessions = await sessions.active();
      for (final a in activeSessions) {
        if (a.session.isActive) {
          await scheduleFor(a.session);
        }
      }

      final activeGroups = await groups.activeGroups();
      for (final g in activeGroups) {
        if (g.group.isActive) {
          await scheduleForGroup(g.group);
        }
      }
    } catch (e) {
      debugPrint('SessionReminders.syncActive failed: $e');
    }
  }
}
