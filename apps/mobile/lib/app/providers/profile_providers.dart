/// Riverpod wiring for the staff member's own details and the staff terms
/// gate (online only).
library;

import 'dart:async';

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/data/local/database.dart';
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
/// answer, so a member already let in keeps working offline; so does a cold
/// start offline, from the last answer this device's database remembers.
class TermsGateController extends Notifier<TermsGate> {
  Future<void>? _running;
  String _okKey = '';

  @override
  TermsGate build() {
    final cloud = ref.watch(cloudBindingProvider) != null;
    final who = ref.watch(authControllerProvider
        .select((u) => u == null ? null : (id: u.id, owner: u.isOwner)));
    // Owner level publishes the terms; the offline demo has none.
    if (!cloud || who == null || who.owner) return const TermsGateOpen();
    _okKey = 'terms_ok:${who.id}';
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
    final db = ref.read(databaseProvider);
    switch (res) {
      case Ok(value: final s):
        state =
            s.mustAccept ? TermsGateBlocked(s.latest!) : const TermsGateOpen();
        await _remember(db, open: !s.mustAccept);
      case Err(failure: final f):
        if (state is TermsGateOpen || state is TermsGateBlocked) return;
        // Offline at a cold start: a member this device last let in keeps
        // working (the floor must run through an outage); the next check
        // online decides again.
        final open = f.code == 'offline' && await _wasOpen(db);
        if (!ref.mounted) return;
        state = open ? const TermsGateOpen() : TermsGateFailed(f);
    }
  }

  Future<bool> _wasOpen(AppDatabase db) async =>
      (await (db.select(db.syncMeta)..where((t) => t.key.equals(_okKey)))
              .getSingleOrNull())
          ?.value ==
      '1';

  Future<void> _remember(AppDatabase db, {required bool open}) => db
      .into(db.syncMeta)
      .insertOnConflictUpdate(SyncMetaRow(key: _okKey, value: open ? '1' : '0'));

  /// The server recorded the acceptance of the version shown.
  void accepted() {
    state = const TermsGateOpen();
    unawaited(_remember(ref.read(databaseProvider), open: true));
  }
}

final termsGateProvider =
    NotifierProvider<TermsGateController, TermsGate>(TermsGateController.new);
