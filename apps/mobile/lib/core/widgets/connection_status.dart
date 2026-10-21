import 'package:arena_ops/app/router/app_nav.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/features/sync/presentation/sync_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest connection status (spec §4). The staff must never mistake stale data
/// for live data.
///
/// Local-only mode shows "Local mode · saved on this device" — there is no
/// server to be offline from. Cloud mode shows the sync engine's real state:
/// synced, changes waiting, syncing, offline (with how much is waiting), a
/// sign-in problem, and how many refused changes need attention. Tapping it in
/// cloud mode opens the Sync screen.
class ConnectionStatus extends ConsumerWidget {
  const ConnectionStatus({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final cloud = ref.watch(cloudBindingProvider) != null;
    final s = ref.watch(syncStatusProvider).value ?? SyncStatus.localOnly;
    final attention =
        s.needsAttention == 0 ? '' : ' · ${s.needsAttention} need attention';

    final (IconData icon, String label, String detail, Color dot) =
        switch (s.state) {
      SyncState.localOnly => (
          Icons.smartphone_outlined,
          'Local mode',
          'Saved on this device',
          arena.primary,
        ),
      SyncState.synced => (
          Icons.cloud_done_outlined,
          'Synced',
          'Up to date$attention',
          s.needsAttention == 0 ? arena.success : arena.danger,
        ),
      SyncState.pending => (
          Icons.cloud_upload_outlined,
          '${s.pending} waiting',
          'Saved here, sending$attention',
          arena.warning,
        ),
      SyncState.syncing => (
          Icons.sync,
          'Syncing',
          s.pending == 0
              ? 'Checking for changes$attention'
              : '${s.pending} to send$attention',
          arena.info,
        ),
      SyncState.offline => (
          Icons.cloud_off_outlined,
          'Offline',
          s.pending == 0
              ? 'Showing what this device last saw$attention'
              : '${s.pending} saved here, not sent yet$attention',
          arena.warning,
        ),
      SyncState.authProblem => (
          Icons.lock_outline,
          s.accessRevoked ? 'Access off' : 'Sign in again',
          'Changes stay on this device',
          arena.danger,
        ),
      SyncState.error => (
          Icons.error_outline,
          'Sync error',
          'Retrying$attention',
          arena.danger,
        ),
    };

    final strip = Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
              AppSpacing.x5, 0, AppSpacing.x5, AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: arena.surface,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: arena.border),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(icon, size: 16, color: arena.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Text(label,
                style: ArenaType.label.copyWith(color: arena.text, fontSize: 13)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '· $detail',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArenaType.caption.copyWith(color: arena.textMuted),
              ),
            ),
            if (cloud) Icon(Icons.chevron_right, size: 16, color: arena.textSubtle),
          ],
        ),
      ),
    );
    if (!cloud) return strip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AppNav.to(context, const SyncScreen()),
      child: strip,
    );
  }
}
