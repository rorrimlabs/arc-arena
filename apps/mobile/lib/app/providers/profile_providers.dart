/// Riverpod wiring for the staff member's own details and the staff terms
/// gate (online only).
library;

import 'dart:async';

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/remote/unavailable_profile_repository.dart';
import 'package:arena_ops/domain/profile/staff_details.dart';
import 'package:arena_ops/domain/profile/staff_terms.dart';
import 'package:arena_ops/domain/repositories/profile_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Overridden in cloud mode with the server-backed repository.
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => const UnavailableProfileRepository(),
);

final myStaffDetailsProvider = FutureProvider.autoDispose<Result<StaffDetails>>(
  (ref) => ref.watch(profileRepositoryProvider).myDetails(),
);

/// Whether the signed-in member may use the app, as far as the staff terms go.
sealed class TermsGate {
  const TermsGate();
}

/// Not known yet (first check running): the app stays closed.
final class TermsGateChecking extends TermsGate {
  const TermsGateChecking();
}

/// No terms to accept: demo mode, owner level, none published, or accepted.
final class TermsGateOpen extends TermsGate {
  const TermsGateOpen();
}

/// [terms] are in force and not accepted yet.
final class TermsGateBlocked extends TermsGate {
  const TermsGateBlocked(this.terms);
  final StaffTerms terms;
}

/// The first check could not run: the app stays closed until it can.
final class TermsGateFailed extends TermsGate {
  const TermsGateFailed(this.failure);
  final Failure failure;
}

/// Checks the terms after sign-in and again whenever the app comes back to
/// the foreground. Fail-closed: until a check says otherwise the app is not
/// shown. A re-check that cannot run (offline on resume) keeps the last
/// answer, so a member already let in keeps working offline.
class TermsGateController extends Notifier<TermsGate> {
  Future<void>? _running;

  @override
  TermsGate build() {
    final cloud = ref.watch(cloudBindingProvider) != null;
    final who = ref.watch(authControllerProvider
        .select((u) => u == null ? null : (id: u.id, owner: u.isOwner)));
    // Owner level publishes the terms; the offline demo has none.
    if (!cloud || who == null || who.owner) return const TermsGateOpen();
    final resumed = AppLifecycleListener(onResume: () => unawaited(check()));
    ref.onDispose(resumed.dispose);
    Future.microtask(check);
    return const TermsGateChecking();
  }

  /// Runs the check (joins one already running).
  Future<void> check() => _running ??= _check().whenComplete(() => _running = null);

  Future<void> _check() async {
    if (state is TermsGateFailed) state = const TermsGateChecking();
    final res = await ref.read(profileRepositoryProvider).termsStatus();
    if (!ref.mounted) return;
    state = switch (res) {
      Ok(value: final s) =>
        s.mustAccept ? TermsGateBlocked(s.latest!) : const TermsGateOpen(),
      Err(failure: final f) => switch (state) {
          TermsGateOpen() || TermsGateBlocked() => state,
          _ => TermsGateFailed(f),
        },
    };
  }

  /// The server recorded the acceptance of the version shown.
  void accepted() => state = const TermsGateOpen();
}

final termsGateProvider =
    NotifierProvider<TermsGateController, TermsGate>(TermsGateController.new);
