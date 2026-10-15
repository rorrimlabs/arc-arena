/// What the venue calls the things it rents out, set by the owner on the admin dashboard and
/// synced as the `venue_profile` setting (`{resource_noun}`): a pool hall has tables, a turf
/// has grounds, a gaming centre has stations.
///
/// Labels only: never pricing, availability or permissions. The server validates the noun
/// (`_venue_profile`); this side still reads it tolerantly so a newer noun never breaks a device.
library;

import 'package:meta/meta.dart';

/// The nouns the server accepts, with the words the floor shows.
enum ResourceNoun {
  station('station', 'Station', 'Stations'),
  table('table', 'Table', 'Tables'),
  ground('ground', 'Ground', 'Grounds'),
  court('court', 'Court', 'Courts'),
  machine('machine', 'Machine', 'Machines'),
  room('room', 'Room', 'Rooms');

  const ResourceNoun(this.code, this.one, this.many);

  final String code;

  /// "Table" — a heading or a label for one.
  final String one;

  /// "Tables" — a heading for the list.
  final String many;

  /// "table" — inside a sentence ("Add your first table").
  String get word => code;
}

@immutable
class VenueProfile {
  const VenueProfile({required this.resourceNoun});

  /// Before the owner sets one (every arena created before profiles existed): stations.
  static const defaults = VenueProfile(resourceNoun: ResourceNoun.station);

  final ResourceNoun resourceNoun;

  /// Reads the synced setting tolerantly: an unknown or missing noun falls back to [defaults].
  factory VenueProfile.fromJson(Map<String, dynamic> json) {
    final code = json['resource_noun'];
    for (final n in ResourceNoun.values) {
      if (n.code == code) return VenueProfile(resourceNoun: n);
    }
    return defaults;
  }

  @override
  bool operator ==(Object other) => other is VenueProfile && other.resourceNoun == resourceNoun;

  @override
  int get hashCode => resourceNoun.hashCode;
}
