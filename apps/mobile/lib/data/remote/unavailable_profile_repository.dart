/// Profile and terms in local-only mode: the details explain they need the
/// online arena; there are no terms to accept (the offline demo has none).
library;

import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/profile_failures.dart';
import 'package:arena_ops/domain/profile/staff_details.dart';
import 'package:arena_ops/domain/profile/staff_terms.dart';
import 'package:arena_ops/domain/repositories/profile_repository.dart';

class UnavailableProfileRepository implements ProfileRepository {
  const UnavailableProfileRepository();

  @override
  Future<Result<StaffDetails>> myDetails() async => const Err(ProfileFailures.cloudOnly);

  @override
  Future<Result<void>> saveDetails(StaffDetailsCommand cmd) async =>
      const Err(ProfileFailures.cloudOnly);

  @override
  Future<Result<TermsStatus>> termsStatus() async => const Ok(TermsStatus());

  @override
  Future<Result<DateTime>> acceptTerms(TermsAcceptCommand cmd) async =>
      const Err(ProfileFailures.cloudOnly);
}
