import 'package:flutter/foundation.dart';

/// Configuration for offline local notification alerts (sound, vibration, intervals).
@immutable
class NotificationSettings {
  const NotificationSettings({
    this.vibrationEnabled = true,
    this.soundEnabled = true,
    this.alert5Min = true,
    this.alert1Min = true,
    this.alertAtEnd = true,
    this.alarmDurationSeconds = 15,
  });

  /// Whether phone vibration is enabled for local timer alerts.
  final bool vibrationEnabled;

  /// Whether sound is played for local timer alerts.
  final bool soundEnabled;

  /// Whether to fire an alert 5 minutes before session ends.
  final bool alert5Min;

  /// Whether to fire an alert 1 minute before session ends (spec: "1 min mune alert").
  final bool alert1Min;

  /// Whether to fire an alert when the session time expires ("സമയം കഴിഞ്ഞു").
  final bool alertAtEnd;

  /// Duration in seconds to play audible ring when an alert triggers (default 15s).
  final int alarmDurationSeconds;

  Map<String, dynamic> toJson() => {
        'vibrationEnabled': vibrationEnabled,
        'soundEnabled': soundEnabled,
        'alert5Min': alert5Min,
        'alert1Min': alert1Min,
        'alertAtEnd': alertAtEnd,
        'alarmDurationSeconds': alarmDurationSeconds,
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
        soundEnabled: json['soundEnabled'] as bool? ?? true,
        alert5Min: json['alert5Min'] as bool? ?? true,
        alert1Min: json['alert1Min'] as bool? ?? true,
        alertAtEnd: json['alertAtEnd'] as bool? ?? true,
        alarmDurationSeconds: json['alarmDurationSeconds'] as int? ?? 15,
      );

  NotificationSettings copyWith({
    bool? vibrationEnabled,
    bool? soundEnabled,
    bool? alert5Min,
    bool? alert1Min,
    bool? alertAtEnd,
    int? alarmDurationSeconds,
  }) =>
      NotificationSettings(
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        alert5Min: alert5Min ?? this.alert5Min,
        alert1Min: alert1Min ?? this.alert1Min,
        alertAtEnd: alertAtEnd ?? this.alertAtEnd,
        alarmDurationSeconds:
            alarmDurationSeconds ?? this.alarmDurationSeconds,
      );

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.vibrationEnabled == vibrationEnabled &&
      other.soundEnabled == soundEnabled &&
      other.alert5Min == alert5Min &&
      other.alert1Min == alert1Min &&
      other.alertAtEnd == alertAtEnd &&
      other.alarmDurationSeconds == alarmDurationSeconds;

  @override
  int get hashCode => Object.hash(
        vibrationEnabled,
        soundEnabled,
        alert5Min,
        alert1Min,
        alertAtEnd,
        alarmDurationSeconds,
      );
}
