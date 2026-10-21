import 'package:flutter/foundation.dart';

/// Configuration for offline local notification alerts (sound, vibration, intervals).
///
/// Kept per device (the local settings table), never synced: each phone on the
/// floor decides how it rings. A key missing from the stored JSON — written by
/// an older build — reads as its default, so an update changes nothing.
@immutable
class NotificationSettings {
  const NotificationSettings({
    this.enabled = true,
    this.vibrationEnabled = true,
    this.soundEnabled = true,
    this.alert5Min = true,
    this.alert1Min = true,
    this.alertAtEnd = true,
    this.ringUntilSeen = true,
  });

  /// The master "Timer alerts" switch: off, no session alert is set at all.
  final bool enabled;

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

  /// The time-up alert keeps ringing until someone opens or clears it
  /// (Android; an iPhone plays the sound once).
  final bool ringUntilSeen;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'vibrationEnabled': vibrationEnabled,
    'soundEnabled': soundEnabled,
    'alert5Min': alert5Min,
    'alert1Min': alert1Min,
    'alertAtEnd': alertAtEnd,
    'ringUntilSeen': ringUntilSeen,
  };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        enabled: json['enabled'] as bool? ?? true,
        vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
        soundEnabled: json['soundEnabled'] as bool? ?? true,
        alert5Min: json['alert5Min'] as bool? ?? true,
        alert1Min: json['alert1Min'] as bool? ?? true,
        alertAtEnd: json['alertAtEnd'] as bool? ?? true,
        ringUntilSeen: json['ringUntilSeen'] as bool? ?? true,
      );

  NotificationSettings copyWith({
    bool? enabled,
    bool? vibrationEnabled,
    bool? soundEnabled,
    bool? alert5Min,
    bool? alert1Min,
    bool? alertAtEnd,
    bool? ringUntilSeen,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    alert5Min: alert5Min ?? this.alert5Min,
    alert1Min: alert1Min ?? this.alert1Min,
    alertAtEnd: alertAtEnd ?? this.alertAtEnd,
    ringUntilSeen: ringUntilSeen ?? this.ringUntilSeen,
  );

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.enabled == enabled &&
      other.vibrationEnabled == vibrationEnabled &&
      other.soundEnabled == soundEnabled &&
      other.alert5Min == alert5Min &&
      other.alert1Min == alert1Min &&
      other.alertAtEnd == alertAtEnd &&
      other.ringUntilSeen == ringUntilSeen;

  @override
  int get hashCode => Object.hash(
    enabled,
    vibrationEnabled,
    soundEnabled,
    alert5Min,
    alert1Min,
    alertAtEnd,
    ringUntilSeen,
  );
}
