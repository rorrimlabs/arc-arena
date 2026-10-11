import 'dart:convert';

import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:drift/drift.dart' show OrderingMode, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What this device has not yet got onto the server, and what the server
/// refused. Nothing here is ever dropped silently: a refused change (a session
/// another device beat us to, a payment for it) stays listed with the server's
/// reason — and the amount — until someone marks it seen.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final binding = ref.watch(cloudBindingProvider);
    final status = ref.watch(syncStatusProvider).value ?? SyncStatus.localOnly;
    final db = ref.watch(databaseProvider);
    final ops = ref.watch(_outboxProvider).value ?? const <SyncOutboxRow>[];
    final refused = [
      for (final o in ops)
        if (o.status == OutboxStatus.rejected && o.resolvedAt == null) o,
    ];
    final waiting = [
      for (final o in ops)
        if (o.status == OutboxStatus.pending) o,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: binding == null
          ? const Center(child: Text('This device is in local-only mode.'))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(binding.arenaName, style: ArenaType.h2.copyWith(color: arena.text)),
                Text('Signed in as ${binding.email}',
                    style: ArenaType.caption.copyWith(color: arena.textMuted)),
                const SizedBox(height: AppSpacing.md),
                Text(_describe(status),
                    style: ArenaType.body.copyWith(color: arena.text)),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: status.state == SyncState.syncing
                      ? null
                      : () => binding.engine.syncNow(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                if (status.state == SyncState.authProblem &&
                    !status.accessRevoked) ...[
                  const SizedBox(height: AppSpacing.sm),
                  // Unsent changes stay in this person's database file and go
                  // as soon as they sign in again on this device.
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      binding.signOut();
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in again'),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Text('Needs attention (${refused.length})',
                    style: ArenaType.h3.copyWith(color: arena.text)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The server refused these. This device has been put back in '
                  'step with the server, so the change is NOT on the floor — '
                  'redo it if it is still right. Money listed here was taken '
                  'on this device but is not recorded on the server.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                for (final o in refused)
                  _OpTile(
                    op: o,
                    db: db,
                    trailing: TextButton(
                      onPressed: () => binding.engine.acknowledge(o.opId),
                      child: const Text('Seen'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text('Waiting to send (${waiting.length})',
                    style: ArenaType.h3.copyWith(color: arena.text)),
                const SizedBox(height: AppSpacing.xs),
                Text('Saved on this device. They go to the server, in order, '
                    'as soon as it can be reached.',
                    style: ArenaType.caption.copyWith(color: arena.textMuted)),
                for (final o in waiting) _OpTile(op: o, db: db),
              ],
            ),
    );
  }

  static String _describe(SyncStatus s) => switch (s.state) {
        SyncState.localOnly => 'Local-only mode: nothing is shared.',
        SyncState.synced => s.lastSyncedAt == null
            ? 'Up to date.'
            : 'Up to date (last synced ${IstTime.format12(s.lastSyncedAt!)}).',
        SyncState.pending => '${s.pending} change(s) waiting to send.',
        SyncState.syncing => 'Syncing…',
        SyncState.offline => 'Offline. ${s.pending} change(s) are saved on this '
            'device and will send when the server can be reached.',
        SyncState.authProblem => s.message ?? 'Sign in again to keep syncing.',
        SyncState.error => s.message ?? 'Sync failed; retrying.',
      };
}

final _outboxProvider = StreamProvider.autoDispose<List<SyncOutboxRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.syncOutbox)
        ..where((t) => t.status.isIn([OutboxStatus.pending, OutboxStatus.rejected]))
        ..orderBy([(t) => OrderingTerm(expression: t.seq, mode: OrderingMode.desc)]))
      .watch();
});

class _OpTile extends StatelessWidget {
  const _OpTile({required this.op, required this.db, this.trailing});
  final SyncOutboxRow op;
  final AppDatabase db;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    final reason = op.errorCode == null ? null : reasonFor(op.errorCode!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(labelFor(op.kind, payload)),
      subtitle: Text([
        IstTime.format12(op.createdAt),
        ?reason,
      ].join(' · '),
          style: ArenaType.caption.copyWith(
              color: reason == null ? arena.textMuted : arena.danger)),
      trailing: trailing,
    );
  }
}

/// A person-readable name for an op.
String labelFor(String kind, Map<String, dynamic> p) => switch (kind) {
      'session.start' => p['booking_id'] != null ? 'Check-in' : 'Start session',
      'session.reconfigure' => 'Change system / game / controllers',
      'session.extend' => 'Extend +${p['added_minutes']} min',
      'session.end' => 'End session (bill '
          '${Paise((p['billed_amount_paise'] as num?)?.toInt() ?? 0).display})',
      'session.void' => 'Void session',
      'payment.record' => '${p['is_refund'] == true ? 'Refund' : 'Payment'} '
          '${Paise(((p['amount_paise'] as num?)?.toInt() ?? 0).abs()).display} '
          '(${p['method']})',
      'group.create' => 'Start group',
      'group.add' => 'Add player',
      'group.switch' => 'Move player',
      'group.end_player' => 'Player leaves',
      'group.extend' => 'Extend group +${p['added_minutes']} min',
      'group.end' => 'End group',
      'group.void' => 'Void group',
      'controller.move' => 'Move controller',
      'customer.create' => 'New customer ${p['name'] ?? ''}',
      'customer.update' => 'Edit customer',
      'booking.create' => 'New booking',
      'booking.update' => 'Edit booking',
      'booking.set_status' => 'Booking ${p['status']}',
      'staff.update' => 'Staff change',
      _ => 'Settings change ($kind)',
    };

/// Why the server refused, in words staff can act on.
String reasonFor(String code) => switch (code) {
      'resource_busy' => 'that station was already in use (another device '
          'started it first)',
      'controller_taken' => 'a controller was already in use',
      'controller_elsewhere' => 'a controller had been moved to another station',
      'controllers_unavailable' => 'not enough free controllers at that station',
      'stale' => 'it was changed on another device first — check and redo',
      'not_active' => 'it had already been ended on another device',
      'booking_not_open' => 'the booking was already checked in or cancelled',
      'booking_conflict' => 'that time on that station was already booked',
      'forbidden' => 'your account is not allowed to do this',
      'voided' => 'it had been voided',
      'not_found' => 'it does not exist on the server (an earlier step was refused)',
      'duplicate' => 'already recorded',
      'players_exceeded' => 'too many players for that game',
      'not_playable' => 'that game cannot run on that station',
      'mode_locked' => 'that station is locked to another mode',
      'last_settings_holder' => 'someone must keep access to Settings',
      _ => 'refused ($code)',
    };
