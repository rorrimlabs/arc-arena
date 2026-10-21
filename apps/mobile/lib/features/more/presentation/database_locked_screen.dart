/// Shown instead of the app when the local database could not be protected.
///
/// Reached only when a schema migration is pending *and* no verified backup
/// could be taken. Opening the database in that state would migrate the single
/// copy of the centre's sessions, bookings and takings with no way back, so the
/// app stops here on purpose and tells staff what to do.
library;

import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/data/local/db_safety.dart';
import 'package:flutter/material.dart';

class DatabaseLockedApp extends StatelessWidget {
  const DatabaseLockedApp({required this.report, super.key});

  final DbProtectReport report;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'arena_ops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: DatabaseLockedScreen(report: report),
    );
  }
}

class DatabaseLockedScreen extends StatelessWidget {
  const DatabaseLockedScreen({required this.report, super.key});

  final DbProtectReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onDisk = report.onDiskSchemaVersion;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 44, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Data kept safe — app not started',
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(
                    'This build needs to upgrade the database on this device, '
                    'but a verified backup could not be taken first. The app '
                    'has stopped instead of upgrading, so nothing has been '
                    'changed or lost.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  _Detail(
                      label: 'Database on this device',
                      value: onDisk == null ? 'not readable' : 'version $onDisk'),
                  _Detail(
                      label: 'This app expects',
                      value: 'version ${report.appSchemaVersion}'),
                  _Detail(label: 'Why it stopped', value: report.detail ?? '—'),
                  const SizedBox(height: 20),
                  Text('What to do', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Keep taking cash and write sessions down on paper for now — '
                    'nothing on this device has been lost. Then send this screen '
                    'to whoever maintains the app before reinstalling or clearing '
                    'app data, because clearing it is what would destroy the '
                    'records.',
                    style: theme.textTheme.bodyMedium,
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

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
