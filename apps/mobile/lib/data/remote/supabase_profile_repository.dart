/// [ProfileRepository] straight against the server: the member's own details,
/// the terms in force and their acceptance are read online through RLS; a
/// save or an acceptance goes to sync_push at once.
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/online_calls.dart';
import 'package:arena_ops/data/remote/profile_failures.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/profile/staff_details.dart';
import 'package:arena_ops/domain/profile/staff_terms.dart';
import 'package:arena_ops/domain/repositories/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository({
    required this._client,
    required this._transport,
    required this.arenaId,
    required this.userId,
    required this.deviceId,
    this.timeout = const Duration(seconds: 20),
  });

  final SupabaseClient _client;
  final SyncTransport _transport;
  final String arenaId;
  final String userId;
  final Future<String> Function() deviceId;
  final Duration timeout;

  String? _staffId;

  @override
  Future<Result<StaffDetails>> myDetails() async => _reworded(await onlineRead(
        _client,
        () async {
          // Owner level reads everyone's row: ask for this member's own.
          final row = await _client
              .from('staff_personal_details')
              .select('phone, email, birth_date, blood_group, address_line1, '
                  'address_line2, city, state, pin_code, emergency_name, '
                  'emergency_relation, emergency_phone')
              .eq('staff_id', await _myStaffId())
              .maybeSingle()
              .timeout(timeout);
          return row == null ? StaffDetails.empty : StaffDetails.fromJson(row);
        },
        loadFailed: ProfileFailures.detailsLoadFailed,
      ));

  @override
  Future<Result<void>> saveDetails(StaffDetailsCommand cmd) async {
    final res = await _push('staff_details.save', cmd.opId, cmd.details.toPayload(),
        ProfileFailures.detailsRejected);
    return switch (res) {
      Ok() => const Ok(null),
      Err(failure: final f) => Err(f),
    };
  }

  @override
  Future<Result<TermsStatus>> termsStatus() async => _reworded(await onlineRead(
        _client,
        () async {
          final row = await _client
              .from('staff_terms')
              .select('id, version, title, body, published_at')
              .eq('arena_id', arenaId)
              .order('version', ascending: false)
              .limit(1)
              .maybeSingle()
              .timeout(timeout);
          if (row == null) return const TermsStatus();
          final latest = StaffTerms.fromJson(row);
          final accepted = await _client
              .from('staff_terms_acceptances')
              .select('id')
              .eq('staff_id', await _myStaffId())
              .eq('terms_id', latest.id)
              .limit(1)
              .timeout(timeout);
          return TermsStatus(latest: latest, accepted: accepted.isNotEmpty);
        },
        loadFailed: ProfileFailures.termsLoadFailed,
      ));

  @override
  Future<Result<DateTime>> acceptTerms(TermsAcceptCommand cmd) async {
    final res =
        await _push('terms.accept', cmd.id, cmd.toPayload(), ProfileFailures.termsRejected);
    return switch (res) {
      Ok(value: final r) => Ok(DateTime.parse(r['accepted_at'] as String).toUtc()),
      Err(failure: final f) => Err(f),
    };
  }

  Future<Result<Map<String, dynamic>>> _push(
    String kind,
    String opId,
    Map<String, dynamic> payload,
    Failure Function(String? code, String? detail) rejected,
  ) async =>
      _reworded(await pushNow(
        _transport,
        arenaId: arenaId,
        deviceId: await deviceId(),
        opId: opId,
        kind: kind,
        payload: payload,
        rejected: rejected,
      ));

  static Result<T> _reworded<T>(Result<T> res) => switch (res) {
        Err(failure: final f) => Err(ProfileFailures.reword(f)),
        Ok() => res,
      };

  Future<String> _myStaffId() async {
    final cached = _staffId;
    if (cached != null) return cached;
    final row = await _client
        .from('staff_profiles')
        .select('id')
        .eq('arena_id', arenaId)
        .eq('user_id', userId)
        .single()
        .timeout(timeout);
    return _staffId = row['id'] as String;
  }
}
