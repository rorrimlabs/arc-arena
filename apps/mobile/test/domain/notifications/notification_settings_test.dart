import 'package:arena_ops/domain/notifications/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings stored by an older build read with the new switches on', () {
    // What the phone holds from before the master switch and ring-until-seen.
    final old = NotificationSettings.fromJson({
      'vibrationEnabled': false,
      'soundEnabled': true,
      'alert5Min': false,
      'alert1Min': true,
      'alertAtEnd': true,
    });
    expect(old.enabled, isTrue);
    expect(old.ringUntilSeen, isTrue);
    expect(old.vibrationEnabled, isFalse, reason: 'what was set is kept');
    expect(old.alert5Min, isFalse);
  });

  test('an empty record is every default: alerts on, ringing until seen', () {
    final s = NotificationSettings.fromJson({});
    expect(s, const NotificationSettings());
    expect(s.enabled && s.alert5Min && s.alert1Min && s.alertAtEnd, isTrue);
    expect(s.soundEnabled && s.vibrationEnabled && s.ringUntilSeen, isTrue);
  });

  test('round-trips through JSON', () {
    const s = NotificationSettings(
      enabled: false,
      vibrationEnabled: false,
      soundEnabled: false,
      alert5Min: false,
      alert1Min: false,
      alertAtEnd: false,
      ringUntilSeen: false,
    );
    expect(NotificationSettings.fromJson(s.toJson()), s);
    expect(
      NotificationSettings.fromJson(const NotificationSettings().toJson()),
      const NotificationSettings(),
    );
  });

  test('copyWith changes only what it is given', () {
    final s = const NotificationSettings().copyWith(enabled: false);
    expect(s.enabled, isFalse);
    expect(s, const NotificationSettings(enabled: false));
    expect(s.copyWith(ringUntilSeen: false).enabled, isFalse);
  });
}
