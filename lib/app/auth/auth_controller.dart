/// Who is signed in right now, and the login/logout actions.
///
/// Kept in memory (not persisted): the counter device requires a PIN each
/// launch, matching the design's lock-first behaviour for a shared device.
library;

import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/data/local/local_user_repository.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/repositories/user_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => LocalUserRepository(
    ref.watch(databaseProvider),
    ref.watch(clockProvider),
  ),
);

/// Active accounts for the login picker.
final usersProvider = FutureProvider.autoDispose<List<AppUser>>(
  (ref) => ref.watch(userRepositoryProvider).activeUsers(),
);

/// The signed-in user, or null when locked.
final authControllerProvider =
    NotifierProvider<AuthController, AppUser?>(AuthController.new);

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
    if (attempt is PinAccepted) state = attempt.user;
    return attempt;
  }

  void signOut() => state = null;
}
