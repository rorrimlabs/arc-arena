import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/features/floor/presentation/sheets/session_expiry_sheet.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Floating in-app alarm heads-up banner shown at the top of the viewport
/// when a session deadline alert triggers in the foreground.
class SessionAlarmOverlay extends ConsumerWidget {
  const SessionAlarmOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarm = ref.watch(sessionAlarmControllerProvider);
    final arena = context.arena;

    final activeSessions = ref.watch(activeSessionsProvider).value ?? [];
    final matchedSession = alarm == null
        ? null
        : activeSessions.firstWhereOrNull((a) => a.session.id == alarm.sessionId);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: alarm == null
              ? const SizedBox.shrink(key: ValueKey('empty_alarm'))
              : _AlarmCard(
                  key: ValueKey('${alarm.sessionId}_${alarm.slot}_${alarm.isSilenced}'),
                  alarm: alarm,
                  arena: arena,
                  onSilence: () =>
                      ref.read(sessionAlarmControllerProvider.notifier).silence(),
                  onDismiss: () =>
                      ref.read(sessionAlarmControllerProvider.notifier).dismiss(),
                  onAction: matchedSession == null
                      ? null
                      : () {
                          ref.read(sessionAlarmControllerProvider.notifier).silence();
                          showSessionExpirySheet(context, matchedSession);
                        },
                ),
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    super.key,
    required this.alarm,
    required this.arena,
    required this.onSilence,
    required this.onDismiss,
    this.onAction,
  });

  final ActiveAlarmState alarm;
  final ArenaColors arena;
  final VoidCallback onSilence;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final bool isCompleted = alarm.isCompleted;
    final Color toneColor = isCompleted ? Red404.r400 : Amber404.a400;
    final Color toneSoft = isCompleted ? const Color(0x28FF3B30) : const Color(0x28FF9500);
    final IconData toneIcon = isCompleted ? Icons.alarm_on_rounded : Icons.hourglass_bottom_rounded;

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        decoration: BoxDecoration(
          color: arena.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: toneColor.withValues(alpha: 0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: toneColor.withValues(alpha: 0.18),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: toneSoft,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Icon(toneIcon, color: toneColor, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                alarm.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ArenaType.label.copyWith(
                                  color: arena.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (!alarm.isSilenced) ...[
                              const SizedBox(width: AppSpacing.xs),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: toneColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'RINGING',
                                  style: ArenaType.micro.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          alarm.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ArenaType.caption.copyWith(
                            color: arena.textMuted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!alarm.isSilenced) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        side: BorderSide(color: arena.border),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onSilence,
                      icon: Icon(Icons.volume_off_rounded, size: 16, color: arena.text),
                      label: Text(
                        'Silence',
                        style: ArenaType.caption.copyWith(color: arena.text, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (onAction != null) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: toneColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onAction,
                      icon: const Icon(Icons.touch_app_rounded, size: 16),
                      label: Text(
                        'Resolve',
                        style: ArenaType.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      side: BorderSide(color: arena.border),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onDismiss,
                    icon: Icon(Icons.close_rounded, size: 16, color: arena.textMuted),
                    label: Text(
                      'Dismiss',
                      style: ArenaType.caption.copyWith(color: arena.textMuted, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
