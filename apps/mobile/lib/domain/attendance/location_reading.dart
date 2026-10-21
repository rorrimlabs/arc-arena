/// One reading of the phone's position, taken at the moment of a clock-in or
/// clock-out (never in the background), and the port that takes it.
library;

import 'package:meta/meta.dart';

/// Why a reading has — or has no — position.
enum LocationStatus {
  /// A fix was captured.
  ok('ok'),

  /// The person refused location for the app (it can still be asked again).
  denied('denied'),

  /// Refused for good: only the phone's Settings can turn it back on.
  deniedForever('denied'),

  /// Location services are switched off on the phone.
  gpsOff('gps_off'),

  /// No fix arrived in time.
  timeout('timeout'),

  /// The platform could not give a position for another reason.
  unavailable('unavailable');

  const LocationStatus(this.wire);

  /// The value the server stores (`attendance_punches.location_status`).
  final String wire;
}

@immutable
class LocationReading {
  const LocationReading.fix({
    required double this.lat,
    required double this.lng,
    required double this.accuracyM,
    this.isMocked,
  }) : status = LocationStatus.ok;

  /// A reading without a position, for every status but [LocationStatus.ok].
  const LocationReading.none(this.status)
      : assert(status != LocationStatus.ok, 'a fix needs a position'),
        lat = null,
        lng = null,
        accuracyM = null,
        isMocked = null;

  final LocationStatus status;
  final double? lat;
  final double? lng;

  /// Horizontal accuracy in metres, as the phone reported it.
  final double? accuracyM;

  /// True when the phone reported a mock (fake) location; null when it cannot
  /// tell.
  final bool? isMocked;

  bool get hasFix => status == LocationStatus.ok;

  /// The `location` object of an `attendance.punch` op.
  Map<String, dynamic> toWire() => {
        'status': status.wire,
        if (hasFix) ...{
          'lat': lat,
          'lng': lng,
          'accuracy_m': double.parse(accuracyM!.toStringAsFixed(1)),
          'is_mocked': isMocked,
        },
      };

  @override
  bool operator ==(Object other) =>
      other is LocationReading &&
      other.status == status &&
      other.lat == lat &&
      other.lng == lng &&
      other.accuracyM == accuracyM &&
      other.isMocked == isMocked;

  @override
  int get hashCode => Object.hash(status, lat, lng, accuracyM, isMocked);

  @override
  String toString() => hasFix
      ? 'LocationReading($lat, $lng ±${accuracyM}m${isMocked == true ? ' mock' : ''})'
      : 'LocationReading(${status.name})';
}

/// Takes one foreground reading, asking for permission when it has not been
/// decided yet. Never throws: every failure is a [LocationReading.none].
abstract interface class LocationProbe {
  Future<LocationReading> read();
}

/// Lets the app send people to the phone's settings when location is off.
abstract interface class LocationSettingsOpener {
  /// The app's own permission page (location refused for good).
  Future<void> openAppSettings();

  /// The phone's location services page (GPS switched off).
  Future<void> openLocationSettings();
}
