/// Saving your own details and accepting the staff terms. Any active member
/// may, for themselves; the server re-checks every field and only lets the
/// version in force be accepted.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/profile_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/remote/profile_failures.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/profile/staff_details.dart';
import 'package:arena_ops/domain/profile/staff_terms.dart';
import 'package:arena_ops/domain/repositories/profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class ProfileActions {
  ProfileActions({
    required this.profile,
    required this.clock,
    this.guard = const PermissionGuard(null),
  });

  final ProfileRepository profile;
  final Clock clock;
  final PermissionGuard guard;

  static const _uuid = Uuid();

  /// Shown with the field errors of [checkDetails], and when loading fails.
  static const Failure fieldsToFix = ProfileFailures.fieldsToFix;
  static const Failure detailsLoadFailed = ProfileFailures.detailsLoadFailed;

  /// The fields of [d] the server would refuse, each with what to fix.
  Map<StaffDetailsField, Failure> checkDetails(StaffDetails d) => {
        for (final f in invalidStaffDetails(d, today: IstDate.fromUtc(clock.now())))
          f: ProfileFailures.invalidField(f),
      };

  /// A save of [d]; keep it to send again after a dropped connection.
  StaffDetailsCommand prepareDetails(StaffDetails d) =>
      StaffDetailsCommand(opId: _uuid.v4(), details: d);

  Future<Result<void>> saveDetails(StaffDetailsCommand cmd) async {
    final denied = guard.checkSignedIn();
    if (denied != null) return Err(denied);
    final invalid = checkDetails(cmd.details);
    if (invalid.isNotEmpty) return Err(invalid.values.first);
    final res = await profile.saveDetails(cmd);
    if (res.isOk) {
      AppTelemetry.addBreadcrumb(category: 'profile', message: 'details_saved');
    }
    return res;
  }

  /// An acceptance of [terms]; keep it to send again after a dropped
  /// connection.
  TermsAcceptCommand prepareAcceptance(StaffTerms terms) => TermsAcceptCommand(
        id: _uuid.v4(),
        termsId: terms.id,
        deviceAt: deviceNow(clock),
      );

  /// Returns the server's accepted_at.
  Future<Result<DateTime>> acceptTerms(TermsAcceptCommand cmd) async {
    final denied = guard.checkSignedIn();
    if (denied != null) return Err(denied);
    final res = await profile.acceptTerms(cmd);
    if (res.isOk) {
      AppTelemetry.addBreadcrumb(category: 'profile', message: 'terms_accepted');
    }
    return res;
  }
}

final profileActionsProvider = Provider<ProfileActions>(
  (ref) => ProfileActions(
    profile: ref.watch(profileRepositoryProvider),
    clock: ref.watch(clockProvider),
    guard: PermissionGuard(ref.watch(authControllerProvider)),
  ),
);
