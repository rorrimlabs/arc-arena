/// Plain-language labels for attendance verdicts, flags and location states.
library;

import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:flutter/material.dart';

String verdictLabel(GeofenceVerdict v) => switch (v) {
      GeofenceVerdict.inside => 'Inside',
      GeofenceVerdict.outside => 'Outside',
      GeofenceVerdict.unknown => 'Location unknown',
    };

({Color fg, Color bg}) verdictColors(BuildContext context, GeofenceVerdict v) {
  final arena = context.arena;
  return switch (v) {
    GeofenceVerdict.inside => (fg: arena.success, bg: arena.successSoft),
    GeofenceVerdict.outside => (fg: arena.danger, bg: arena.dangerSoft),
    GeofenceVerdict.unknown => (fg: arena.warning, bg: arena.warningSoft),
  };
}

/// "Inside · 42 m · ±8 m" for a reading judged by [preview].
String readingSummary(LocationReading reading, PunchPreview preview) {
  if (!reading.hasFix) return locationStatusLabel(reading.status);
  final parts = <String>[
    if (preview.noGeofence) 'Arena location not set' else verdictLabel(preview.verdict),
    if (preview.distanceM != null) '${preview.distanceM} m away',
    '±${reading.accuracyM!.round()} m',
    if (preview.mock) 'fake location',
  ];
  return parts.join(' · ');
}

String locationStatusLabel(LocationStatus s) => switch (s) {
      LocationStatus.ok => 'Location found',
      LocationStatus.denied => 'Location permission is off',
      LocationStatus.deniedForever => 'Location is blocked for this app',
      LocationStatus.gpsOff => 'Location (GPS) is switched off',
      LocationStatus.timeout => 'No GPS fix yet',
      LocationStatus.unavailable => 'Location unavailable',
    };

/// The server's `attendance_punches.location_status` in words.
String wireLocationStatusLabel(String wire) => switch (wire) {
      'ok' => 'GPS fix',
      'denied' => 'Location permission off',
      'gps_off' => 'GPS switched off',
      'timeout' => 'No GPS fix in time',
      _ => 'Location unavailable',
    };

/// Entry flags (outside_in, auto_out, …) in words.
String flagLabel(String flag) {
  final out = flag.endsWith('_out');
  final base = flag.replaceFirst(RegExp(r'_(in|out)$'), '');
  final when = flag == 'auto_out'
      ? ''
      : out
          ? ' (out)'
          : flag.endsWith('_in')
              ? ' (in)'
              : '';
  final what = switch (base) {
    'outside' => 'Outside the arena',
    'unknown' => 'Location unknown',
    'low_accuracy' => 'Weak GPS',
    'no_geofence' => 'Arena location not set',
    'mock' => 'Fake location',
    'auto' when flag == 'auto_out' => 'Closed automatically',
    'past_shift_end' => 'Clocked out late',
    'worked_on_leave' => 'Worked on a leave day',
    _ => flag.replaceAll('_', ' '),
  };
  return '$what$when';
}

String dayStatusLabel(DayStatus s) => switch (s) {
      DayStatus.present => 'Present',
      DayStatus.late => 'Late',
      DayStatus.halfDay => 'Half day',
      DayStatus.absent => 'Absent',
      DayStatus.onLeave => 'On leave',
      DayStatus.halfLeave => 'Half-day leave',
      DayStatus.holiday => 'Holiday',
      DayStatus.weekOff => 'Week off',
      DayStatus.upcoming => 'Scheduled',
      DayStatus.notEmployed => '—',
    };

({Color fg, Color bg}) dayStatusColors(BuildContext context, DayStatus s) {
  final arena = context.arena;
  return switch (s) {
    DayStatus.present => (fg: arena.success, bg: arena.successSoft),
    DayStatus.late || DayStatus.halfDay || DayStatus.halfLeave =>
      (fg: arena.warning, bg: arena.warningSoft),
    DayStatus.absent => (fg: arena.danger, bg: arena.dangerSoft),
    DayStatus.onLeave || DayStatus.holiday => (fg: arena.info, bg: arena.infoSoft),
    _ => (fg: arena.textMuted, bg: arena.surfaceSunken),
  };
}
