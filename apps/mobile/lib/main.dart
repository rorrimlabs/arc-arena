import 'dart:async';
import 'dart:io';

import 'package:arena_ops/app/arena_ops_app.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/app/sync/cloud_root.dart';
import 'package:arena_ops/app/sync/secure_session_storage.dart';
import 'package:arena_ops/core/config/app_config.dart';
import 'package:arena_ops/core/monitoring/sentry_setup.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/db_safety.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/features/more/presentation/database_locked_screen.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;

export 'package:arena_ops/app/arena_ops_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();

  await SentryFlutter.init(
    // DSN, environment, tracing, Session Replay (rates + masking) and the
    // offline-sync beforeSend filter: core/monitoring/sentry_setup.dart.
    (options) => configureSentry(options, config),
    appRunner: () async {
      final problem = config.problemFor(releaseBuild: kReleaseMode);
      if (problem != null) {
        if (config.isSentryEnabled) {
          unawaited(
            Sentry.captureMessage(
              'Startup configuration problem: $problem',
              level: SentryLevel.fatal,
            ),
          );
        }
        runApp(SentryWidget(child: _ConfigProblemApp(problem)));
        return;
      }
      if (config.isSupabase) {
        // Cloud mode: each person signs in with their own account; the arena's
        // data lives in its own database file (the local-only file is untouched).
        await Supabase.initialize(
          url: config.supabaseUrl!,
          publishableKey: config.supabaseAnonKey!,
          authOptions: FlutterAuthClientOptions(
            localStorage: SecureSessionStorage(backendUrl: config.supabaseUrl!),
          ),
        );
        final documents = await getApplicationDocumentsDirectory();
        runApp(SentryWidget(child: CloudRoot(documentsPath: documents.path)));
        return;
      }

      // The counter device holds the only copy of the day's takings, and Drift
      // migrates the file the instant it opens. So: back it up and verify the
      // backup FIRST, and refuse to open at all if a migration is pending and no
      // verified backup could be taken (spec: no destructive migration before
      // backup verification).
      final documents = await getApplicationDocumentsDirectory();
      final dbPath = '${documents.path}/arena_ops.sqlite';
      final safety = await DbSafety.protect(
        dbFile: File(dbPath),
        appSchemaVersion: AppDatabase.expectedSchemaVersion,
        backupDir: Directory('${documents.path}/arena_ops-backups'),
      );
      debugPrint('DbSafety: $safety');
      if (!safety.safeToOpen) {
        // Opening here would migrate the only copy with no way back.
        runApp(SentryWidget(child: DatabaseLockedApp(report: safety)));
        return;
      }

      // Local-first: open the on-device database and seed the catalog on first run.
      // The explicit path is the same file the backup above protected.
      final db = AppDatabase(
        driftDatabase(
          name: 'arena_ops',
          native: DriftNativeOptions(databasePath: () async => dbPath),
        ),
      );
      try {
        await LocalSeed.applyIfEmpty(db).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('LocalSeed startup warning: $e');
      }
      if (db.rebuiltFromVersion != 0) {
        // Not silent: the pre-release schema had no forward path, so the rows now
        // live only in the backup taken moments ago.
        debugPrint(
          'DbSafety: rebuilt from v${db.rebuiltFromVersion}; '
          'previous data is in ${safety.backupFile?.path}',
        );
      }

      // One container so startup reminder setup and the UI share the same wiring.
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );

      // No auto-login: the counter device is shared and sits in public, so every
      // launch starts locked at the PIN screen and the signed-in user is whoever
      // actually typed a PIN. The router sends an unauthenticated session to
      // /login.

      // Booking reminders (spec §23): ask permission once, then reconcile the
      // device's scheduled reminders with the current bookings (de-dupes on
      // restart). Fire-and-forget so it never delays first paint, and failures here
      // never block the app.
      unawaited(_initReminders(container));

      runApp(
        SentryWidget(
          child: UncontrolledProviderScope(
            container: container,
            child: const ArenaOpsApp(),
          ),
        ),
      );
    },
  );
}

Future<void> _initReminders(ProviderContainer container) async {
  try {
    final service = container.read(notificationServiceProvider);
    await service.init();
    await service.requestPermission();
    await container.read(bookingRemindersProvider).syncUpcoming();
  } catch (e) {
    debugPrint('reminder init skipped: $e');
  }
}

/// Shown instead of the app when the build's configuration is unusable.
class _ConfigProblemApp extends StatelessWidget {
  const _ConfigProblemApp(this.problem);
  final String problem;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(problem, textAlign: TextAlign.center)),
        ),
      ),
    ),
  );
}
