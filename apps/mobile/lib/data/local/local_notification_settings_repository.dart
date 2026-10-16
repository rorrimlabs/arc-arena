import 'dart:convert';

import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:arena_ops/domain/repositories/notification_settings_repository.dart';

class LocalNotificationSettingsRepository
    implements NotificationSettingsRepository {
  LocalNotificationSettingsRepository(this._db);

  final AppDatabase _db;
  static const _key = 'notification_settings';

  @override
  Future<NotificationSettings> getSettings() async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(_key)))
        .getSingleOrNull();
    if (row == null) return const NotificationSettings();
    try {
      return NotificationSettings.fromJson(
        jsonDecode(row.json) as Map<String, dynamic>,
      );
    } catch (_) {
      return const NotificationSettings();
    }
  }

  @override
  Stream<NotificationSettings> watchSettings() {
    return (_db.select(_db.settings)..where((t) => t.key.equals(_key)))
        .watchSingleOrNull()
        .map((row) {
      if (row == null) return const NotificationSettings();
      try {
        return NotificationSettings.fromJson(
          jsonDecode(row.json) as Map<String, dynamic>,
        );
      } catch (_) {
        return const NotificationSettings();
      }
    });
  }

  @override
  Future<void> saveSettings(NotificationSettings settings) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: _key,
            json: jsonEncode(settings.toJson()),
          ),
        );
  }
}
