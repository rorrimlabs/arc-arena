/// The arena's attendance rules (settings key `attendance`) and a preview of
/// how the server will judge a reading against them.
///
/// The server decides; [previewPunch] only lets the clock screen say "Inside ·
/// 42 m" or warn "Outside — clock-in will be refused" before the punch is sent.
/// It mirrors op_attendance_punch and _geo_distance_m.
library;

import 'dart:math' as math;

import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:meta/meta.dart';

/// What happens to a punch that is outside the geofence or whose position is
/// unknown.
enum OutsideRule { block, flag, allow }

/// What happens when the phone reports a mock (fake) location.
enum MockRule { block, flag }

/// The server's verdict on a punch's position.
enum GeofenceVerdict {
  inside('inside'),
  outside('outside'),
  unknown('unknown');

  const GeofenceVerdict(this.wire);
  final String wire;

  static GeofenceVerdict fromWire(String? wire) => switch (wire) {
        'inside' => inside,
        'outside' => outside,
        _ => unknown,
      };
}

@immutable
class Geofence {
  const Geofence({required this.lat, required this.lng, required this.radiusM});

  final double lat;
  final double lng;
  final int radiusM;

  static Geofence? fromJson(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'], lng = json['lng'], radius = json['radius_m'];
    if (lat is! num || lng is! num || radius is! num) return null;
    return Geofence(
        lat: lat.toDouble(), lng: lng.toDouble(), radiusM: radius.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is Geofence &&
      other.lat == lat &&
      other.lng == lng &&
      other.radiusM == radiusM;

  @override
  int get hashCode => Object.hash(lat, lng, radiusM);
}

@immutable
class AttendanceRules {
  const AttendanceRules({
    this.geofence,
    this.outsideRule = OutsideRule.flag,
    this.minAccuracyM = 50,
    this.mockRule = MockRule.block,
    this.maxOpenHours = 14,
  });

  /// What a new arena starts with (the server's _attendance_rules defaults).
  static const AttendanceRules defaults = AttendanceRules();

  final Geofence? geofence;
  final OutsideRule outsideRule;
  final int minAccuracyM;
  final MockRule mockRule;
  final int maxOpenHours;

  /// Whether clock-ins are checked against the arena's location at all. With
  /// [OutsideRule.allow] every punch is accepted wherever it happens (the
  /// default for a new arena), so staff are not shown where they were.
  bool get checksLocation => outsideRule != OutsideRule.allow;

  /// The stored setting over [defaults]; unknown or missing values keep the
  /// default, as the server does.
  factory AttendanceRules.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    T pick<T extends Enum>(List<T> values, Object? wire, T fallback) =>
        values.firstWhere((v) => v.name == wire, orElse: () => fallback);
    return AttendanceRules(
      geofence: Geofence.fromJson(json['geofence']),
      outsideRule:
          pick(OutsideRule.values, json['outside_rule'], defaults.outsideRule),
      minAccuracyM:
          (json['min_accuracy_m'] as num?)?.toInt() ?? defaults.minAccuracyM,
      mockRule: pick(MockRule.values, json['mock_rule'], defaults.mockRule),
      maxOpenHours:
          (json['max_open_hours'] as num?)?.toInt() ?? defaults.maxOpenHours,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AttendanceRules &&
      other.geofence == geofence &&
      other.outsideRule == outsideRule &&
      other.minAccuracyM == minAccuracyM &&
      other.mockRule == mockRule &&
      other.maxOpenHours == maxOpenHours;

  @override
  int get hashCode =>
      Object.hash(geofence, outsideRule, minAccuracyM, mockRule, maxOpenHours);
}

/// Great-circle distance in whole metres (haversine, mean Earth radius), as
/// the server's _geo_distance_m computes it.
int distanceMetres(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return (2 * r * math.asin(math.min(1, math.sqrt(a)))).round();
}

/// How the server is expected to judge a reading.
@immutable
class PunchPreview {
  const PunchPreview({
    required this.verdict,
    this.distanceM,
    this.lowAccuracy = false,
    this.mock = false,
    this.noGeofence = false,
    required this.willBeRefused,
    required this.willBeFlagged,
  });

  final GeofenceVerdict verdict;
  final int? distanceM;
  final bool lowAccuracy;
  final bool mock;
  final bool noGeofence;

  /// The punch will be refused (block rule, or a blocked mock location).
  final bool willBeRefused;

  /// The punch will be accepted but put up for review.
  final bool willBeFlagged;
}

PunchPreview previewPunch(LocationReading reading, AttendanceRules rules) {
  final fence = rules.geofence;
  GeofenceVerdict verdict;
  int? distance;
  var low = false;
  if (!reading.hasFix) {
    verdict = GeofenceVerdict.unknown;
  } else if (fence == null) {
    verdict = GeofenceVerdict.unknown;
  } else {
    distance = distanceMetres(reading.lat!, reading.lng!, fence.lat, fence.lng);
    if (reading.accuracyM! > rules.minAccuracyM) {
      verdict = GeofenceVerdict.unknown;
      low = true;
    } else {
      verdict = distance <= fence.radiusM
          ? GeofenceVerdict.inside
          : GeofenceVerdict.outside;
    }
  }
  final mock = reading.hasFix && reading.isMocked == true;
  final off = verdict != GeofenceVerdict.inside;
  return PunchPreview(
    verdict: verdict,
    distanceM: distance,
    lowAccuracy: low,
    mock: mock,
    noGeofence: reading.hasFix && fence == null,
    willBeRefused: (mock && rules.mockRule == MockRule.block) ||
        (off && rules.outsideRule == OutsideRule.block),
    willBeFlagged: (mock && rules.mockRule == MockRule.flag) ||
        (off && rules.outsideRule == OutsideRule.flag),
  );
}
