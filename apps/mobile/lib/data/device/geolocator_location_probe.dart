/// [LocationProbe] on the phone's location services (package:geolocator).
///
/// Foreground only, one reading per punch: asks for "while using the app"
/// permission when it has not been decided, then waits up to [timeLimit] for
/// the best fix the phone can give. Every failure becomes a reading without a
/// position; the server decides what that means for the punch.
library;

import 'dart:async';

import 'package:arena_ops/domain/attendance/location_reading.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GeolocatorLocationProbe implements LocationProbe, LocationSettingsOpener {
  const GeolocatorLocationProbe({this.timeLimit = const Duration(seconds: 15)});

  final Duration timeLimit;

  @override
  Future<LocationReading> read() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationReading.none(LocationStatus.gpsOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const LocationReading.none(LocationStatus.denied);
        case LocationPermission.deniedForever:
          return const LocationReading.none(LocationStatus.deniedForever);
        case LocationPermission.unableToDetermine:
          return const LocationReading.none(LocationStatus.unavailable);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: timeLimit,
        ),
      );
      return LocationReading.fix(
        lat: position.latitude,
        lng: position.longitude,
        accuracyM: position.accuracy,
        // Android reports this reliably; iOS 15+ when the OS knows.
        isMocked: position.isMocked,
      );
    } on TimeoutException {
      return const LocationReading.none(LocationStatus.timeout);
    } on LocationServiceDisabledException {
      return const LocationReading.none(LocationStatus.gpsOff);
    } on PermissionDeniedException {
      return const LocationReading.none(LocationStatus.denied);
    } on Exception catch (e) {
      debugPrint('location reading failed: $e');
      return const LocationReading.none(LocationStatus.unavailable);
    }
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
