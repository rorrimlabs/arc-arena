import 'dart:async';
import 'dart:io';

import 'package:arena_ops/app/arena_ops_app.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/notifications/reminder_startup.dart';
import 'package:arena_ops/app/sync/cloud_root.dart';
import 'package:arena_ops/app/sync/secure_session_storage.dart';
import 'package:arena_ops/core/config/app_config.dart';
import 'package:arena_ops/core/monitoring/sentry_setup.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
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
      final problem = config.problemFor(
        mode: kReleaseMode
            ? BuildMode.release
            : kProfileMode
            ? BuildMode.profile
            : BuildMode.debug,
      );
      if (problem != null) {
        if (config.isSentryEnabled) {
          unawaited(
            Sentry.captureMessage(
              'Startup configuration problem: $problem',
              level: SentryLevel.fatal,
            ),
          );
        }
        runApp(SentryWidget(child: ConfigProblemApp(problem)));
        return;
      }
      if (config.isSupabase) {
        // Cloud mode: each person signs in with their own account; the arena's
        // data lives in its own database file (the local-only file is untouched).
        try {
          await Supabase.initialize(
            url: config.supabaseUrl!,
            publishableKey: config.supabaseAnonKey!,
            authOptions: FlutterAuthClientOptions(
              localStorage: SecureSessionStorage(
                backendUrl: config.supabaseUrl!,
              ),
            ),
          );
          final documents = await getApplicationDocumentsDirectory();
          runApp(SentryWidget(child: CloudRoot(documentsPath: documents.path)));
          return;
        } catch (e, stack) {
          // No network is needed here (the saved sign-in is read from the
          // keystore and refreshed later), so this is an error on the device.
          debugPrint('Supabase initialization failed: $e\n$stack');
          if (config.isSentryEnabled) {
            unawaited(Sentry.captureException(e, stackTrace: stack));
          }
          runApp(SentryWidget(child: ConfigProblemApp.startupFailed('$e')));
          return;
        }
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

      // Booking reminders and session timer alerts (spec §23): ask permission
      // once, then rebuild the device's scheduled alerts from the database
      // (de-dupes on restart; running sessions ring again after a restart).
      // Fire-and-forget so it never delays first paint, and failures here never
      // block the app.
      unawaited(startReminders(container));

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

/// Shown instead of the app when it cannot start.
class ConfigProblemApp extends StatelessWidget {
  /// The build's configuration is unusable: only a corrected build fixes it.
  const ConfigProblemApp(this.problem, {super.key}) : startupFailed = false;

  /// Cloud mode failed to set up on this device; [problem] is the error.
  const ConfigProblemApp.startupFailed(this.problem, {super.key})
    : startupFailed = true;

  final String problem;
  final bool startupFailed;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'arena_ops',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.dark,
    home: ConfigProblemScreen(problem: problem, startupFailed: startupFailed),
  );
}

class ConfigProblemScreen extends StatelessWidget {
  const ConfigProblemScreen({
    required this.problem,
    this.startupFailed = false,
    super.key,
  });
  final String problem;
  final bool startupFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 44,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    startupFailed
                        ? 'App could not start on this device'
                        : 'Configuration problem — app not started',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    startupFailed
                        ? 'Something on this device failed while the app was '
                              'getting ready to sign in. No records were changed.'
                        : 'The app was prevented from starting because the current '
                              'build configuration or environment is invalid or incomplete.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          startupFailed ? 'Error details' : 'Why it stopped',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          problem,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('What to do', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    startupFailed
                        ? '• Close the app completely and open it again.\n'
                              '• If it happens again, restart the device.\n'
                              '• Still stuck: tell the owner and show them the error details above.\n'
                              '• Do not uninstall the app or clear its data: records not yet '
                              'sent would be lost.'
                        : '• Local development: build with --flavor dev\n'
                              '• Staging: build with --flavor staging --dart-define-from-file=dart_define.staging.json\n'
                              '• Production: build with --flavor prod --dart-define-from-file=dart_define.prod.json '
                              'in profile or release mode (debug is refused).',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
