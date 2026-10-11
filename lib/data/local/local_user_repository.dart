import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/pin_credential.dart';
import 'package:arena_ops/domain/repositories/user_repository.dart';
import 'package:drift/drift.dart';

class LocalUserRepository implements UserRepository {
  LocalUserRepository(this._db, [this._clock = const SystemClock()]);

  final AppDatabase _db;
  final Clock _clock;

  /// Wrong PINs tolerated before the account locks. Five is enough for a
  /// mistyped PIN on a busy counter and far too few to walk 10 000 of them.
  static const maxAttempts = 5;

  /// Lockout after the 5th, 6th, 7th... consecutive failure. Escalating, so a
  /// patient guesser is slowed down far more than fumbling staff.
  static const lockoutLadder = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  AppUser _map(UserRow r) => AppUser(
        id: r.id,
        name: r.name,
        perms: Permission.parse(r.perms),
        active: r.active,
      );

  @override
  Future<List<AppUser>> activeUsers() async {
    final rows = await (_db.select(_db.users)
          ..where((t) => t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return rows.map(_map).toList();
  }

  @override
  Future<List<AppUser>> all() async {
    final rows = await (_db.select(_db.users)
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
    return rows.map(_map).toList();
  }

  @override
  Future<AppUser> upsert(AppUser user, {String? newPin}) async {
    final existing = await _row(user.id);
    final credential = newPin == null ? null : PinCredential.create(newPin);
    await _db.into(_db.users).insertOnConflictUpdate(UsersCompanion(
          id: Value(user.id),
          name: Value(user.name),
          perms: Value(Permission.codesOf(user.perms)),
          active: Value(user.active),
          // Omitting a PIN keeps the stored one; there is no way to read it
          // back, so "unchanged" has to mean "write the same hash again".
          pinSalt: Value(credential?.salt ?? existing?.pinSalt),
          pinHash: Value(credential?.hash ?? existing?.pinHash),
          pinIterations:
              Value(credential?.iterations ?? existing?.pinIterations),
          // A new PIN clears a lockout; so does reactivating an account.
          failedAttempts:
              credential == null ? Value(existing?.failedAttempts ?? 0) : const Value(0),
          lockedUntilAt: credential == null
              ? Value(existing?.lockedUntilAt)
              : const Value(null),
          sortOrder: Value(existing?.sortOrder ?? 0),
        ));
    return (await getById(user.id))!;
  }

  @override
  Future<AppUser?> getById(String id) async {
    final r = await _row(id);
    return r == null ? null : _map(r);
  }

  @override
  Future<bool> hasPin(String id) async {
    final r = await _row(id);
    return r?.pinHash != null && r?.pinSalt != null;
  }

  @override
  Future<void> clearLockout(String id) async {
    await (_db.update(_db.users)..where((t) => t.id.equals(id))).write(
      const UsersCompanion(
        failedAttempts: Value(0),
        lockedUntilAt: Value(null),
      ),
    );
  }

  @override
  Future<PinAttempt> verify(String id, String pin) async {
    // One transaction, so two quick taps cannot both read "4 attempts used"
    // and each be allowed a 5th.
    return _db.transaction(() async {
      final row = await _row(id);
      if (row == null) return const PinUnavailable('No such account.');
      if (!row.active) return const PinUnavailable('This account is turned off.');

      final salt = row.pinSalt;
      final hash = row.pinHash;
      final iterations = row.pinIterations;
      if (salt == null || hash == null || iterations == null) {
        return const PinUnavailable('No PIN is set for this account.');
      }

      final now = _clock.now();
      final lockedUntil = row.lockedUntilAt;
      if (lockedUntil != null && lockedUntil.isAfter(now)) {
        // Locked: the PIN is not even checked, so guessing buys no information.
        return PinLockedOut(
          until: lockedUntil,
          retryIn: lockedUntil.difference(now),
        );
      }

      final credential =
          PinCredential(salt: salt, hash: hash, iterations: iterations);
      if (credential.matches(pin)) {
        await (_db.update(_db.users)..where((t) => t.id.equals(id))).write(
          const UsersCompanion(
            failedAttempts: Value(0),
            lockedUntilAt: Value(null),
          ),
        );
        return PinAccepted(_map(row));
      }

      // The count deliberately survives an expired lockout, so each further
      // wrong PIN climbs the ladder. Resetting it here would hand a guesser
      // five fresh attempts every 30 seconds — enough to walk all 10 000
      // four-digit PINs in a day. Only a correct PIN, a new PIN or an owner
      // clearing the lockout resets it.
      final failures = row.failedAttempts + 1;

      if (failures < maxAttempts) {
        await (_db.update(_db.users)..where((t) => t.id.equals(id)))
            .write(UsersCompanion(failedAttempts: Value(failures)));
        return PinRejected(attemptsLeft: maxAttempts - failures);
      }

      final rung = (failures - maxAttempts).clamp(0, lockoutLadder.length - 1);
      final until = now.add(lockoutLadder[rung]);
      await (_db.update(_db.users)..where((t) => t.id.equals(id))).write(
        UsersCompanion(
          failedAttempts: Value(failures),
          lockedUntilAt: Value(until),
        ),
      );
      return PinLockedOut(until: until, retryIn: until.difference(now));
    });
  }

  Future<UserRow?> _row(String id) =>
      (_db.select(_db.users)..where((t) => t.id.equals(id))).getSingleOrNull();
}
