/// Who is signed in right now, and the login/logout actions.
///
/// Kept in memory (not persisted): the counter device requires a PIN each
/// launch, matching the design's lock-first behaviour for a shared device.
library;

import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:arena_ops/data/local/local_user_repository.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/repositories/user_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => LocalUserRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
    ref.watch(syncRecorderProvider),
  ),
);

/// Active accounts for the login picker.
final usersProvider = FutureProvider.autoDispose<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).activeUsers(),
);

/// The signed-in user, or null when locked.
final authControllerProvider = NotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  /// Checks the PIN for [userId] and signs in on success.
  ///
  /// The returned [PinAttempt] is what the keypad shows: a wrong PIN with the
  /// attempts remaining, or a lockout with the wait. There is deliberately no
  /// way to become signed in without passing through here.
  Future<PinAttempt> signIn(String userId, String pin) async {
    final attempt = await ref.read(userRepositoryProvider).verify(userId, pin);
    final accepted = attempt is PinAccepted;
    AppTelemetry.staffAuth(
      operation: 'login',
      userId: userId,
      success: accepted,
    );
    if (accepted) state = attempt.user;
    return attempt;
  }

  void signOut() {
    final currentId = state?.id ?? 'unknown';
    AppTelemetry.staffAuth(operation: 'logout', userId: currentId);
    state = null;
  }
}

/// Cloud mode: the person signed in on this device is the Supabase account
/// (their own login, on their own device). There is no PIN step — a PIN hash
/// on the device proves nothing to the server. Their permissions come from
/// the synced staff list and follow an owner's edits live; if their access is
/// turned off, the app drops back to the sign-in gate.
class CloudAuthController extends AuthController {
  CloudAuthController(this._initial);
  final AppUser _initial;

  @override
  AppUser? build() {
    final binding = ref.watch(cloudBindingProvider)!;
    final db = ref.watch(databaseProvider);
    final sub = (db.select(db.users)..where((t) => t.id.equals(binding.userId)))
        .watchSingleOrNull()
        .listen((row) {
          if (row == null || !row.active) {
            state = null;
            binding.signOut();
            return;
          }
          state = AppUser(
            id: row.id,
            name: row.name,
            perms: Permission.parse(row.perms),
          );
        });
    ref.onDispose(sub.cancel);
    return _initial;
  }

  @override
  Future<PinAttempt> signIn(String userId, String pin) async =>
      const PinUnavailable('This device is signed in with your account.');

  @override
  void signOut() {
    state = null;
    ref.read(cloudBindingProvider)?.signOut();
  }
}
