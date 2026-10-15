/// How each alert rings is chosen here, not in the plugin wrapper: on Android
/// 8+ the channel decides sound and vibration, so "sound off" must pick a
/// silent channel, and only time up may ring as an alarm and repeat.
library;

import 'package:arena_ops/core/notifications/alert_channels.dart';
import 'package:arena_ops/domain/notifications/reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReminderPlan plan(
    AlertKind kind, {
    bool sound = true,
    bool vibrate = true,
    bool ringUntilSeen = false,
  }) => ReminderPlan(
    id: 1,
    sessionId: kind == AlertKind.booking ? null : 's1',
    fireAtUtc: DateTime.utc(2026, 10, 2, 13, 30),
    title: 't',
    body: 'b',
    kind: kind,
    playSound: sound,
    enableVibration: vibrate,
    ringUntilSeen: ringUntilSeen,
  );

  test('a booking reminder keeps the booking channel', () {
    expect(
      alertStyleFor(plan(AlertKind.booking)),
      const AlertStyle(channel: AlertChannels.booking),
    );
  });

  test('a warning uses the channel for its sound + vibration mix, never an '
      'alarm, never repeating', () {
    final cases = {
      (true, true): AlertChannels.warningSoundVibrate,
      (true, false): AlertChannels.warningSound,
      (false, true): AlertChannels.vibrateOnly,
      (false, false): AlertChannels.silent,
    };
    for (final MapEntry(key: (sound, vibrate), value: channel)
        in cases.entries) {
      final style = alertStyleFor(
        plan(
          AlertKind.warning,
          sound: sound,
          vibrate: vibrate,
          ringUntilSeen: true,
        ),
      );
      expect(style.channel, channel, reason: 'sound $sound vibrate $vibrate');
      expect(style.channel.sound, sound);
      expect(style.channel.vibrate, vibrate);
      expect(style.alarm, isFalse);
      expect(style.insistent, isFalse);
    }
  });

  test('time up rings on the alarm stream when sound is on', () {
    final both = alertStyleFor(plan(AlertKind.timeUp));
    expect(both.channel, AlertChannels.timeUpSoundVibrate);
    expect(both.channel.alarm, isTrue);
    expect(both.alarm, isTrue);

    final soundOnly = alertStyleFor(plan(AlertKind.timeUp, vibrate: false));
    expect(soundOnly.channel, AlertChannels.timeUpSound);
    expect(soundOnly.channel.vibrate, isFalse);
  });

  test('time up with sound off uses the matching quiet channel, still an '
      'alarm', () {
    final buzz = alertStyleFor(plan(AlertKind.timeUp, sound: false));
    expect(buzz.channel, AlertChannels.vibrateOnly);
    expect(buzz.alarm, isTrue);

    final silent = alertStyleFor(
      plan(AlertKind.timeUp, sound: false, vibrate: false),
    );
    expect(silent.channel, AlertChannels.silent);
    expect(silent.channel.sound, isFalse);
  });

  test('time up repeats only when ringing until seen, and only with '
      'something to repeat', () {
    expect(
      alertStyleFor(plan(AlertKind.timeUp, ringUntilSeen: true)).insistent,
      isTrue,
    );
    expect(alertStyleFor(plan(AlertKind.timeUp)).insistent, isFalse);
    expect(
      alertStyleFor(plan(AlertKind.timeUp, sound: false, ringUntilSeen: true))
          .insistent,
      isTrue,
      reason: 'vibrate-only keeps buzzing',
    );
    expect(
      alertStyleFor(
        plan(
          AlertKind.timeUp,
          sound: false,
          vibrate: false,
          ringUntilSeen: true,
        ),
      ).insistent,
      isFalse,
    );
    expect(androidFlagInsistent, 4, reason: 'Notification.FLAG_INSISTENT');
  });

  test('every channel is created at start-up under its own id, and the old '
      'channels that ignored "sound off" are removed', () {
    final ids = [for (final c in AlertChannels.all) c.id];
    expect(ids.toSet(), hasLength(ids.length));
    for (final kind in AlertKind.values) {
      for (final sound in [true, false]) {
        for (final vibrate in [true, false]) {
          final style = alertStyleFor(
            plan(kind, sound: sound, vibrate: vibrate),
          );
          expect(ids, contains(style.channel.id));
        }
      }
    }
    for (final old in AlertChannels.obsoleteIds) {
      expect(ids, isNot(contains(old)));
    }
    expect(
      AlertChannels.all.where((c) => c.alarm),
      everyElement(predicate<AlertChannel>((c) => c.sound)),
      reason: 'an alarm channel always has a sound to play',
    );
  });
}
