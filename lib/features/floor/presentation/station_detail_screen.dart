import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:arena_ops/features/floor/presentation/sheets/change_controllers_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/change_game_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/end_session_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/extend_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/session_history_sheet.dart';
import 'package:arena_ops/features/floor/presentation/sheets/switch_system_sheet.dart';
import 'package:arena_ops/features/games/presentation/controls_sheet.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen detail for one live session (design station detail). Shows the
/// hero timer, progress, due-so-far, players and the games this session, and
/// hosts every in-session action — all of which route to the existing sheets,
/// so no billing/timing logic changes here.
class StationDetailScreen extends ConsumerWidget {
  const StationDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final sessions = ref.watch(activeSessionsProvider).value ?? const [];
    final match = sessions.where((s) => s.session.id == sessionId).toList();

    if (match.isEmpty) {
      // Session ended (e.g. billed) — leave the detail.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final a = match.first;
    final session = a.session;
    final current = a.current;
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();
    final timer = SessionTimer(
      startedAt: session.startedAt,
      scheduledEndAt: session.scheduledEndAt,
    );
    final visual = timer.state(now);
    final overtime = visual == SessionVisualState.overtime;
    final (Color accent, String badge) = switch (visual) {
      SessionVisualState.normal => (arena.stPlaying, 'Playing'),
      SessionVisualState.warning => (arena.stEnding, 'Ending'),
      SessionVisualState.overtime => (arena.stOvertime, 'Over time'),
    };

    final resources = ref.watch(resourcesProvider).value ?? const [];
    final activities = ref.watch(activitiesProvider).value ?? const [];
    final resName = resources
        .where((r) => r.id == current.resourceId)
        .map((r) => r.name)
        .firstOrNull;
    final activity =
        activities.where((x) => x.code == current.activityCode).firstOrNull;
    final usesControllers = activity?.usesControllers ?? false;
    final usesGames = activity?.usesGames ?? false;
    final game = current.gameId == null
        ? null
        : ref.watch(gameByIdProvider(current.gameId!)).value;
    final customer = ref.watch(customerByIdProvider(session.customerId)).value;

    final booked = session.scheduledEndAt.difference(session.startedAt);
    final elapsed = timer.elapsed(now);
    final progress =
        booked.inSeconds == 0 ? 0.0 : (elapsed.inSeconds / booked.inSeconds);
    final due = ref.watch(sessionActionsProvider).liveBill(a, now).total;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(resName ?? current.resourceId,
                style: ArenaType.h3.copyWith(color: arena.text, fontSize: 18)),
            Text(
              [
                if (activity != null) activity.name else current.activityCode,
                if (current.controllerCount != null)
                  controllersLabel(current.controllerCount!),
              ].join(' · '),
              style: ArenaType.caption.copyWith(color: arena.textMuted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Center(child: StatusDotLabel(label: badge, color: accent)),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: arena.text),
            color: arena.surfaceRaised,
            onSelected: (v) {
              switch (v) {
                case 'controls':
                  if (current.gameId != null) {
                    showControlsSheet(context, current.gameId!);
                  }
                case 'switch':
                  showSwitchSystemSheet(context, a);
                case 'game':
                  showChangeGameSheet(context, a);
                case 'controllers':
                  showChangeControllersSheet(context, a);
                case 'history':
                  showSessionHistorySheet(context, a);
              }
            },
            itemBuilder: (context) => [
              if (current.gameId != null)
                const PopupMenuItem(value: 'controls', child: Text('Controls')),
              const PopupMenuItem(value: 'switch', child: Text('Switch system')),
              if (usesGames)
                const PopupMenuItem(value: 'game', child: Text('Change game')),
              if (usesControllers)
                const PopupMenuItem(
                    value: 'controllers', child: Text('Controllers')),
              const PopupMenuItem(value: 'history', child: Text('History')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.x5, AppSpacing.lg, AppSpacing.x5, AppSpacing.xxl),
        children: [
          // Hero timer.
          Text(
            overtime
                ? '+${formatClock(timer.overtime(now))}'
                : formatClock(timer.remaining(now)),
            style: ArenaType.timer.copyWith(
              fontSize: 72,
              color: overtime ? arena.stOvertime : arena.text,
            ),
          ),
          Text(overtime ? 'over the clock' : 'left on the clock',
              style: ArenaType.body.copyWith(color: arena.textMuted)),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: arena.tmTrack,
              color: overtime ? arena.stOvertime : arena.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text('${elapsed.inMinutes}m played',
                  style: ArenaType.caption.copyWith(color: arena.textMuted)),
              const Spacer(),
              Text(
                '${formatMinutesLabel(booked)} booked · from ${IstTime.format12(session.startedAt)}',
                style: ArenaType.caption.copyWith(color: arena.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _InfoCard(
                    label: 'Due so far',
                    value: Paise(due.value).display,
                    valueStyle: ArenaType.h1.copyWith(color: arena.text),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _InfoCard(
                    label: 'Now playing',
                    value:
                        game?.name ?? (usesGames ? 'No game' : (activity?.name ?? '—')),
                    valueStyle: ArenaType.h3.copyWith(color: arena.text, fontSize: 18),
                    sub: customer?.displayName,
                  ),
                ),
              ],
            ),
          ),
          if (current.controllerCount != null && current.controllerCount! > 0) ...[
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 1; i <= current.controllerCount!; i++)
                  _PlayerChip(
                    index: i,
                    name: i == 1 ? customer?.displayName : null,
                  ),
              ],
            ),
            // The physical pads this session holds, by the label written on
            // them, so staff know exactly which pads to collect at the end.
            Builder(builder: (context) {
              final labels = {
                for (final c in ref.watch(controllersProvider).value ?? const [])
                  c.id: c.label,
              };
              final pads = [
                for (final al
                    in ref.watch(openPadAllocationsProvider).value ?? const [])
                  if (al.segmentId == current.id)
                    labels[al.controllerId] ?? al.controllerId,
              ]..sort();
              if (pads.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text('Controllers: ${pads.join(', ')}',
                    key: const ValueKey('session-pads'),
                    style: ArenaType.caption.copyWith(color: arena.textMuted)),
              );
            }),
          ],
          const SizedBox(height: AppSpacing.x10),
          _GamesThisSession(segments: a.segments),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        onExtend: () => showExtendSheet(context, a),
        onBill: () => showEndSessionSheet(context, a),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.label,
    required this.value,
    required this.valueStyle,
    this.sub,
  });

  final String label;
  final String value;
  final TextStyle valueStyle;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: ArenaType.caption.copyWith(color: arena.textMuted)),
          const SizedBox(height: AppSpacing.sm),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: valueStyle),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ArenaType.caption.copyWith(color: arena.textSubtle)),
          ],
        ],
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.index, this.name});
  final int index;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.md, 4),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: arena.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: arena.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Text('C$index',
                style: ArenaType.micro.copyWith(color: arena.primaryText)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(name ?? 'Player $index',
              style: ArenaType.label.copyWith(color: arena.text)),
        ],
      ),
    );
  }
}

/// "2 controllers" / "1 controller" — never the ungrammatical "1 controllers".
String controllersLabel(int n) => '$n controller${n == 1 ? '' : 's'}';

class _GamesThisSession extends ConsumerWidget {
  const _GamesThisSession({required this.segments});
  final List<SessionSegment> segments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    if (segments.isEmpty) return const SizedBox.shrink();

    // Resolve ids → names so each row reads as the game and the station it was
    // played on (not a generic "Game segment").
    final resNames = {
      for (final r in ref.watch(resourcesProvider).value ?? []) r.id: r.name,
    };
    final gameNames = {
      for (final g in ref.watch(allGamesProvider).value ?? []) g.id: g.name,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GAMES THIS SESSION',
            style: ArenaType.overline.copyWith(color: arena.text)),
        const SizedBox(height: AppSpacing.md),
        for (final s in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.gameId != null
                            ? (gameNames[s.gameId] ?? 'Game')
                            : s.activityCode,
                        style: ArenaType.label.copyWith(color: arena.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          resNames[s.resourceId] ?? s.resourceId,
                          if (s.controllerCount != null)
                            controllersLabel(s.controllerCount!),
                        ].join(' · '),
                        style: ArenaType.caption.copyWith(color: arena.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${IstTime.format12(s.startedAt)} – ${s.endedAt != null ? IstTime.format12(s.endedAt!) : 'now'}',
                  style: AppTextStyles.mono(ArenaType.caption)
                      .copyWith(color: arena.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onExtend, required this.onBill});
  final VoidCallback onExtend;
  final VoidCallback onBill;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      decoration: BoxDecoration(
        color: arena.surface,
        border: Border(top: BorderSide(color: arena.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExtend,
                  icon: const Icon(Icons.more_time, size: 18),
                  label: const Text('Extend'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onBill,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Bill'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
