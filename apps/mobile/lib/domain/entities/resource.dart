import 'package:freezed_annotation/freezed_annotation.dart';

part 'resource.freezed.dart';

/// A physical station/table/room (spec §12). "Occupied" and "Reserved" are NOT
/// stored here — they are derived from open segments and upcoming bookings.
enum ResourceStatus {
  available,
  maintenance,
  temporarilyUnavailable,
  disabled;

  String get code => switch (this) {
        ResourceStatus.available => 'available',
        ResourceStatus.maintenance => 'maintenance',
        ResourceStatus.temporarilyUnavailable => 'temporarily_unavailable',
        ResourceStatus.disabled => 'disabled',
      };

  String get label => switch (this) {
        ResourceStatus.available => 'Available',
        ResourceStatus.maintenance => 'Maintenance',
        ResourceStatus.temporarilyUnavailable => 'Temporarily unavailable',
        ResourceStatus.disabled => 'Disabled',
      };

  /// Short badge text for a station card.
  String get badge => switch (this) {
        ResourceStatus.available => 'Free',
        ResourceStatus.maintenance => 'Maintenance',
        ResourceStatus.temporarilyUnavailable => 'Unavailable',
        ResourceStatus.disabled => 'Disabled',
      };

  /// True when a session may be started on this resource at all.
  bool get isBookable => this == ResourceStatus.available;

  static ResourceStatus fromCode(String c) => switch (c) {
        'available' => ResourceStatus.available,
        'maintenance' => ResourceStatus.maintenance,
        'temporarily_unavailable' => ResourceStatus.temporarilyUnavailable,
        'disabled' => ResourceStatus.disabled,
        _ => throw ArgumentError('Unknown resource status: $c'),
      };
}

enum ResourceKind {
  station,
  table,
  room;

  String get code => name;

  String get label => switch (this) {
        ResourceKind.station => 'Station',
        ResourceKind.table => 'Table',
        ResourceKind.room => 'Room',
      };

  static ResourceKind fromCode(String c) =>
      ResourceKind.values.firstWhere((k) => k.code == c);
}

@freezed
abstract class Resource with _$Resource {
  const factory Resource({
    required String id,
    required String name, // HEX, VOID, RIFT ...
    required ResourceKind kind,
    @Default(ResourceStatus.available) ResourceStatus status,
    @Default(0) int sortOrder,
    // Activity codes this resource can host. RIFT hosts both PS5 and VR.
    @Default(<String>[]) List<String> activityCodes,
    // For a dual-capability station (RIFT): the activity it is currently locked
    // to ('PS5' / 'VR'), or null when not mode-locked. Written only via
    // setResourceMode; preserved across ordinary station edits.
    String? currentMode,
  }) = _Resource;
}
