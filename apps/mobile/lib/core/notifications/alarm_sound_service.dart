import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Platform audio service for loud, repeating physical device session alarms.
/// Uses Android RingtoneManager with AudioAttributes.USAGE_ALARM for loud,
/// audible playback in busy gaming-centre environments.
class AlarmSoundService {
  static const _channel = MethodChannel('in.rorrim.arena_ops/alarm_sound');

  /// Play the system alarm ringtone at alarm stream volume.
  static Future<void> playAlarm() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('playAlarm');
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } catch (_) {
      // Safe fallback on desktop/testing or if channel unavailable
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  /// Stop audio playback immediately.
  static Future<void> stopAlarm() async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('stopAlarm');
      }
    } catch (_) {}
  }

  /// Whether alarm is currently playing.
  static Future<bool> isAlarmPlaying() async {
    try {
      if (Platform.isAndroid) {
        final playing = await _channel.invokeMethod<bool>('isAlarmPlaying');
        return playing ?? false;
      }
    } catch (_) {}
    return false;
  }
}
