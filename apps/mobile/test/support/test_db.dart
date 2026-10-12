import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/notifications/notification_service.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Signs tests in as the seeded owner so they land on the app, not the login
/// screen. Override with [signedInStaff] where a staff view is under test.
class TestOwnerAuth extends AuthController {
  @override
  AppUser? build() => AppUser(
        id: 'u1',
        // A stand-in signed-in owner. Not read from the seed, so renaming the
        // real accounts cannot break the tests that use it.
        name: 'Test Owner',
        perms: Permission.all,
      );
}

/// A staff account (Floor + members; no Money/Reports/Settings) for role tests.
class TestStaffAuth extends AuthController {
  @override
  AppUser? build() => const AppUser(
        id: 'u2',
        name: 'Test Staff',
        perms: {
          Permission.start,
          Permission.bill,
          Permission.discount,
          Permission.members,
        },
      );
}

/// A seeded in-memory database for widget/integration tests.
Future<AppDatabase> seededMemoryDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  await LocalSeed.apply(db);
  return db;
}

/// Provider overrides wiring a test database and (optionally) a fake clock.
/// Return type is inferred (Riverpod's Override) to avoid the dart:core clash.
List<Override> testOverrides(
  AppDatabase db, {
  Clock? clock,
  AuthController Function()? auth,
}) =>
    [
      databaseProvider.overrideWithValue(db),
      // Never touch the platform notification channel in tests.
      notificationServiceProvider
          .overrideWithValue(const NoopNotificationService()),
      // Start signed in (owner by default) so tests skip the PIN login.
      authControllerProvider.overrideWith(auth ?? TestOwnerAuth.new),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ];
