/// The arena's staff terms: append-only versions, the highest in force. A
/// member who is not owner level accepts the version in force before working
/// in the app (op_terms_accept: only the latest can be accepted).
library;

import 'package:meta/meta.dart';

@immutable
class StaffTerms {
  const StaffTerms({
    required this.id,
    required this.version,
    required this.title,
    required this.body,
    required this.publishedAt,
  });

  final String id;
  final int version;
  final String title;

  /// Plain text; paragraphs are separated by blank lines.
  final String body;
  final DateTime publishedAt;

  List<String> get paragraphs => [
        for (final p in body.split(RegExp(r'\n\s*\n')))
          if (p.trim().isNotEmpty) p.trim(),
      ];

  factory StaffTerms.fromJson(Map<String, dynamic> j) => StaffTerms(
        id: j['id'] as String,
        version: (j['version'] as num).toInt(),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        publishedAt: DateTime.parse(j['published_at'] as String).toUtc(),
      );
}

/// The terms in force for the signed-in member, and whether they accepted it.
@immutable
class TermsStatus {
  const TermsStatus({this.latest, this.accepted = false});

  /// Null when the arena has published no terms.
  final StaffTerms? latest;
  final bool accepted;

  bool get mustAccept => latest != null && !accepted;
}

/// An acceptance to send. [id] is also the op id: sending it again after a
/// dropped connection replays it. [deviceAt] is the phone's clock, evidence
/// only (the server stamps accepted_at).
@immutable
class TermsAcceptCommand {
  const TermsAcceptCommand({
    required this.id,
    required this.termsId,
    required this.deviceAt,
  });

  final String id;
  final String termsId;
  final DateTime deviceAt;

  Map<String, dynamic> toPayload() => {
        'id': id,
        'terms_id': termsId,
        'device_at': deviceAt.toUtc().toIso8601String(),
      };
}
