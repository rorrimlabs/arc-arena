import 'package:arena_ops/domain/attendance/attendance_rules.dart';
import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The arena at 12.9716, 77.5946 with a 100 m radius (as in pgTAP 28).
  const fence = Geofence(lat: 12.9716, lng: 77.5946, radiusM: 100);
  const flag = AttendanceRules(geofence: fence);
  const block = AttendanceRules(geofence: fence, outsideRule: OutsideRule.block);

  LocationReading at(double lat, {double acc = 8, bool mock = false}) =>
      LocationReading.fix(lat: lat, lng: 77.5946, accuracyM: acc, isMocked: mock);

  group('AttendanceRules.fromJson', () {
    test('no setting → the server defaults', () {
      expect(AttendanceRules.fromJson(null), AttendanceRules.defaults);
      expect(AttendanceRules.defaults.outsideRule, OutsideRule.flag);
      expect(AttendanceRules.defaults.minAccuracyM, 50);
      expect(AttendanceRules.defaults.mockRule, MockRule.block);
      expect(AttendanceRules.defaults.maxOpenHours, 14);
      expect(AttendanceRules.defaults.geofence, isNull);
    });

    test('reads the stored setting', () {
      final r = AttendanceRules.fromJson({
        'geofence': {'lat': 12.9716, 'lng': 77.5946, 'radius_m': 100},
        'outside_rule': 'block',
        'min_accuracy_m': 30,
        'mock_rule': 'flag',
        'max_open_hours': 12,
      });
      expect(r.geofence, fence);
      expect(r.outsideRule, OutsideRule.block);
      expect(r.minAccuracyM, 30);
      expect(r.mockRule, MockRule.flag);
      expect(r.maxOpenHours, 12);
    });

    test('null geofence and unknown values keep the defaults', () {
      final r = AttendanceRules.fromJson(
          {'geofence': null, 'outside_rule': 'later', 'mock_rule': 7});
      expect(r, AttendanceRules.defaults);
    });
  });

  test('distanceMetres matches the server (_geo_distance_m)', () {
    expect(distanceMetres(12.9716, 77.5946, 12.9726, 77.5946), inInclusiveRange(110, 112));
    expect(distanceMetres(12.9716, 77.5946, 12.9717, 77.5946), 11);
    expect(distanceMetres(12.9716, 77.5946, 12.9760, 77.5946), 489);
    expect(distanceMetres(12.9716, 77.5946, 12.9716, 77.5946), 0);
  });

  group('previewPunch', () {
    test('an accurate fix within the radius is inside, nothing to flag', () {
      final p = previewPunch(at(12.9717), flag);
      expect(p.verdict, GeofenceVerdict.inside);
      expect(p.distanceM, 11);
      expect(p.willBeRefused, isFalse);
      expect(p.willBeFlagged, isFalse);
    });

    test('outside: flagged under flag, refused under block, neither under allow', () {
      expect(previewPunch(at(12.9760), flag).verdict, GeofenceVerdict.outside);
      expect(previewPunch(at(12.9760), flag).willBeFlagged, isTrue);
      expect(previewPunch(at(12.9760), block).willBeRefused, isTrue);
      final allow = previewPunch(at(12.9760),
          const AttendanceRules(geofence: fence, outsideRule: OutsideRule.allow));
      expect(allow.willBeRefused || allow.willBeFlagged, isFalse);
    });

    test('a fix worse than the minimum accuracy is unknown', () {
      final p = previewPunch(at(12.9717, acc: 200), block);
      expect(p.verdict, GeofenceVerdict.unknown);
      expect(p.lowAccuracy, isTrue);
      expect(p.willBeRefused, isTrue);
    });

    test('no fix is unknown', () {
      final p = previewPunch(const LocationReading.none(LocationStatus.gpsOff), flag);
      expect(p.verdict, GeofenceVerdict.unknown);
      expect(p.distanceM, isNull);
      expect(p.willBeFlagged, isTrue);
    });

    test('no geofence set: unknown, and said so', () {
      final p = previewPunch(at(12.9717), AttendanceRules.defaults);
      expect(p.verdict, GeofenceVerdict.unknown);
      expect(p.noGeofence, isTrue);
    });

    test('a mock location is refused under mock block, flagged under mock flag', () {
      expect(previewPunch(at(12.9717, mock: true), flag).willBeRefused, isTrue);
      final p = previewPunch(at(12.9717, mock: true),
          const AttendanceRules(geofence: fence, mockRule: MockRule.flag));
      expect(p.willBeRefused, isFalse);
      expect(p.willBeFlagged, isTrue);
    });
  });

  test('LocationReading.toWire is the op payload shape', () {
    expect(at(12.9717, acc: 8.04).toWire(), {
      'status': 'ok',
      'lat': 12.9717,
      'lng': 77.5946,
      'accuracy_m': 8.0,
      'is_mocked': false,
    });
    expect(const LocationReading.none(LocationStatus.deniedForever).toWire(),
        {'status': 'denied'});
    expect(const LocationReading.none(LocationStatus.gpsOff).toWire(),
        {'status': 'gps_off'});
  });
}
