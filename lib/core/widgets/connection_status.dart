import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/core/config/app_config.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest connection status (spec §4). The staff must never mistake stale data
/// for live data.
///
/// The app is **local-first**: the on-device database is always available, so
/// it shows "Local mode · saved on this device" rather than a misleading
/// Online/Offline pill — there is no server to be offline from.
///
/// Selecting the Supabase backend does **not** currently sync anything (there
/// is no client), so that case says so plainly instead of claiming a cloud.
/// When a sync layer exists, this strip becomes the real Online / Offline +
/// last-synced indicator; the seam is here so no call site has to change.
class ConnectionStatus extends ConsumerWidget {
  const ConnectionStatus({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final arena = context.arena;

    // Local backend (the default): data lives on this device, no network needed.
    final (IconData icon, String label, String detail, Color dot) =
        switch (config.backend) {
      Backend.local => (
          Icons.smartphone_outlined,
          'Local mode',
          'Saved on this device',
          arena.primary,
        ),
      // The Supabase flag is accepted but no sync layer exists yet, so the
      // writes still go to this device only. Saying "syncing enabled" here
      // would be the exact kind of status staff must not have to second-guess.
      Backend.supabase => (
          Icons.cloud_off_outlined,
          'Cloud not wired',
          'Still saved on this device only',
          arena.warning,
        ),
    };

    return Padding(
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
          ],
        ),
      ),
    );
  }
}
