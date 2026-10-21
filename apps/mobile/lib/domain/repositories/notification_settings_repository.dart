import 'package:arena_ops/domain/notifications/notification_settings.dart';

abstract interface class NotificationSettingsRepository {
  Future<NotificationSettings> getSettings();
  Stream<NotificationSettings> watchSettings();
  Future<void> saveSettings(NotificationSettings settings);
}
