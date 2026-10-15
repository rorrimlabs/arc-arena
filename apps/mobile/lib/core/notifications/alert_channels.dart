/// How the phone rings each notification — pure, so it is unit-tested and the
/// plugin wrapper (`notification_service.dart`) only passes it on.
///
/// On Android 8+ the notification CHANNEL, not the notification, decides sound
/// and vibration, and a channel cannot be changed once created. So every
/// (sound, vibrate) mix the alert settings allow has a channel of its own, and
/// "sound off" picks a silent channel instead of asking a sounding one to be
/// quiet (which Android ignores). The time-up alert rings on the alarm stream.
library;

import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:meta/meta.dart';

@immutable
class AlertChannel {
  const AlertChannel(
    this.id,
    this.name,
    this.description, {
    required this.sound,
    required this.vibrate,
    this.alarm = false,
  });

  final String id;
  final String name;
  final String description;
  final bool sound;
  final bool vibrate;

  /// Plays on the alarm stream (AudioAttributes USAGE_ALARM), not the
  /// notification one: louder, and heard when notification sounds are low.
  final bool alarm;

  /// The vibration pattern (ms: wait, buzz, pause, buzz…); time up buzzes
  /// longer.
  List<int> get pattern =>
      alarm ? const [0, 1000, 500, 1000, 500, 1000] : const [0, 500, 250, 500];

  @override
  String toString() => 'AlertChannel($id)';
}

/// Every channel the app posts to, created at start-up.
abstract final class AlertChannels {
  static const booking = AlertChannel(
    'booking_reminders',
    'Booking reminders',
    'Reminders before a booked session starts.',
    sound: true,
    vibrate: true,
  );

  static const warningSoundVibrate = AlertChannel(
    'timer_warning_sound_vibrate',
    'Timer warnings',
    '5 and 1 minutes before a session ends, with sound and vibration.',
    sound: true,
    vibrate: true,
  );
  static const warningSound = AlertChannel(
    'timer_warning_sound',
    'Timer warnings (sound only)',
    '5 and 1 minutes before a session ends, with sound only.',
    sound: true,
    vibrate: false,
  );
  static const vibrateOnly = AlertChannel(
    'timer_alerts_vibrate_only',
    'Timer alerts (vibrate only)',
    'Session timer alerts with vibration and no sound.',
    sound: false,
    vibrate: true,
  );
  static const silent = AlertChannel(
    'timer_alerts_silent',
    'Timer alerts (silent)',
    'Session timer alerts with no sound or vibration.',
    sound: false,
    vibrate: false,
  );

  static const timeUpSoundVibrate = AlertChannel(
    'timer_time_up_sound_vibrate',
    'Time up',
    "A session's time is up: rings as an alarm, with vibration.",
    sound: true,
    vibrate: true,
    alarm: true,
  );
  static const timeUpSound = AlertChannel(
    'timer_time_up_sound',
    'Time up (sound only)',
    "A session's time is up: rings as an alarm.",
    sound: true,
    vibrate: false,
    alarm: true,
  );

  static const all = [
    booking,
    warningSoundVibrate,
    warningSound,
    vibrateOnly,
    silent,
    timeUpSoundVibrate,
    timeUpSound,
  ];

  /// Channels earlier builds created, whose sound could not follow the
  /// settings: removed at start-up so they leave the phone's settings list.
  static const obsoleteIds = [
    'session_alerts_vibrate',
    'session_alerts_no_vibrate',
  ];
}

/// Android's `Notification.FLAG_INSISTENT`: the sound repeats until the
/// notification is opened or cleared.
const int androidFlagInsistent = 4;

@immutable
class AlertStyle {
  const AlertStyle({
    required this.channel,
    this.alarm = false,
    this.insistent = false,
  });

  final AlertChannel channel;

  /// A time-up alert: category alarm, shown in full on the lock screen.
  final bool alarm;

  /// Keeps sounding until opened or cleared ([androidFlagInsistent]).
  final bool insistent;

  @override
  bool operator ==(Object other) =>
      other is AlertStyle &&
      other.channel.id == channel.id &&
      other.alarm == alarm &&
      other.insistent == insistent;

  @override
  int get hashCode => Object.hash(channel.id, alarm, insistent);

  @override
  String toString() =>
      'AlertStyle(${channel.id}, alarm: $alarm, insistent: $insistent)';
}

/// How [plan] rings. A booking reminder keeps its own channel. A 5-/1-minute
/// warning rings once on the channel matching its sound and vibration. Time
/// up rings as an alarm when sound is on; with sound off it uses the matching
/// silent or vibrate-only channel, still marked as an alarm. Only time up
/// ever repeats, and only when [ReminderPlan.ringUntilSeen] — and there is
/// something to repeat.
AlertStyle alertStyleFor(ReminderPlan plan) {
  final sound = plan.playSound;
  final vibrate = plan.enableVibration;
  final once = switch ((sound, vibrate)) {
    (true, true) => AlertChannels.warningSoundVibrate,
    (true, false) => AlertChannels.warningSound,
    (false, true) => AlertChannels.vibrateOnly,
    (false, false) => AlertChannels.silent,
  };
  return switch (plan.kind) {
    AlertKind.booking => const AlertStyle(channel: AlertChannels.booking),
    AlertKind.warning => AlertStyle(channel: once),
    AlertKind.timeUp => AlertStyle(
      channel: switch ((sound, vibrate)) {
        (true, true) => AlertChannels.timeUpSoundVibrate,
        (true, false) => AlertChannels.timeUpSound,
        _ => once,
      },
      alarm: true,
      insistent: plan.ringUntilSeen && (sound || vibrate),
    ),
  };
}
