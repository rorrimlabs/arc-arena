import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:meta/meta.dart';

/// The outcome of a PIN attempt.
///
/// More than a bool because the keypad has to tell staff *why* they are not
/// getting in — a wrong PIN, or an account that has locked itself after too
/// many wrong ones.
@immutable
sealed class PinAttempt {
  const PinAttempt();
}

/// Correct PIN; [user] is signed in.
class PinAccepted extends PinAttempt {
  const PinAccepted(this.user);
  final AppUser user;
}

/// Wrong PIN. [attemptsLeft] is how many remain before the account locks.
class PinRejected extends PinAttempt {
  const PinRejected({required this.attemptsLeft});
  final int attemptsLeft;
}

/// Too many wrong PINs; no attempt was even checked. Unlocks at [until].
class PinLockedOut extends PinAttempt {
  const PinLockedOut({required this.until, required this.retryIn});
  final DateTime until;
  final Duration retryIn;
}

/// The account cannot sign in: no PIN has been set, or it is deactivated.
class PinUnavailable extends PinAttempt {
  const PinUnavailable(this.reason);
  final String reason;
}

abstract interface class UserRepository {
  /// Active accounts for the login picker, in display order.
  Future<List<AppUser>> activeUsers();

  Future<AppUser?> getById(String id);

  /// Checks [pin] for the account [id], applying the failed-attempt lockout.
  ///
  /// This is the only way to authenticate. It has the side effect of recording
  /// the attempt, so it must not be called speculatively.
  Future<PinAttempt> verify(String id, String pin);

  /// Every account, active or not — the Settings → Staff list.
  Future<List<AppUser>> all();

  /// Create or update an account (Settings → Staff).
  ///
  /// [newPin] sets or replaces the PIN; omit it to leave the existing PIN
  /// untouched. A PIN can never be read back, only replaced.
  Future<AppUser> upsert(AppUser user, {String? newPin});

  /// Whether [id] has a usable PIN. Lets Settings warn about an account that
  /// cannot sign in without revealing anything about the PIN itself.
  Future<bool> hasPin(String id);

  /// Clear a lockout (owner action in Settings → Staff).
  Future<void> clearLockout(String id);
}
