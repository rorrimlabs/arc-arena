import 'package:arena_ops/app/controllers/session_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/custom_duration_sheet.dart';
import 'package:arena_ops/domain/entities/session.dart';
import 'package:arena_ops/domain/services/session_planner.dart';
import 'package:arena_ops/domain/services/session_timer.dart';
import 'package:arena_ops/features/floor/presentation/sheets/end_session_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ExpiryActionMode {
  overview,
  extend,
}

/// Modal bottom sheet presented when a session duration expires (spec §13, §14, §19).
/// Freezes billable duration and amount at scheduledEndAt while awaiting staff action.
Future<void> showSessionExpirySheet(
  BuildContext context,
  ActiveSession active, {
  ExpiryActionMode initialMode = ExpiryActionMode.overview,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _SessionExpirySheet(active: active, initialMode: initialMode),
    ),
  );
}

class _SessionExpirySheet extends ConsumerStatefulWidget {
  const _SessionExpirySheet({
    required this.active,
    this.initialMode = ExpiryActionMode.overview,
  });

  final ActiveSession active;
  final ExpiryActionMode initialMode;

  @override
  ConsumerState<_SessionExpirySheet> createState() =>
      _SessionExpirySheetState();
}

class _SessionExpirySheetState extends ConsumerState<_SessionExpirySheet> {
  late ExpiryActionMode _mode;
  int _extendMinutes = 30;
  Result<ExtensionPlan>? _plan;
  bool _previewLoading = false;
  bool _applyingExtension = false;
  bool _openingEnd = false;
  int _previewToken = 0;

  Session get _session => widget.active.session;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (_mode == ExpiryActionMode.extend) {
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    final token = ++_previewToken;
    setState(() => _previewLoading = true);
    final p = await ref.read(sessionActionsProvider).previewExtension(
          _session,
          widget.active.segments,
          _extendMinutes,
        );
    if (!mounted || token != _previewToken) return;
    setState(() {
      _plan = p;
      _previewLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arena = context.arena;
    final now = ref.watch(nowProvider).value ?? ref.watch(clockProvider).now();

    final timer = SessionTimer(
      startedAt: _session.startedAt,
      scheduledEndAt: _session.scheduledEndAt,
      actualEndedAt: _session.actualEndedAt,
    );

    // Bill frozen at scheduledEndAt cutoff (P0 critical requirement)
    final frozenBill = ref.watch(sessionActionsProvider).liveBill(widget.active, now);
    final allocatedDuration = _session.scheduledEndAt.difference(_session.startedAt);
    final customer = ref.watch(customerByIdProvider(_session.customerId)).value;
    final resource = (ref.watch(resourcesProvider).value ?? const [])
        .where((r) => r.id == widget.active.current.resourceId)
        .firstOrNull;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: ListView(
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x28FF3B30),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(Icons.alarm_off_rounded, color: Red404.r400, size: 26),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Expired',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Red404.r400,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${resource?.name ?? 'Station'} • ${customer?.displayName ?? 'Guest'}',
                      style: ArenaType.caption.copyWith(color: arena.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Cutoff Status Banner ──
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: const Color(0x1AFF9500),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: const Color(0x66FF9500)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_clock_rounded, color: Color(0xFFFF9500), size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Billing Frozen at Cutoff',
                        style: ArenaType.label.copyWith(
                          color: const Color(0xFFFF9500),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Automatic extra charges stopped at ${IstTime.format12(_session.scheduledEndAt)}. '
                        'Staff action is required to extend or end the session.',
                        style: ArenaType.caption.copyWith(color: arena.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Session Metrics Grid ──
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: arena.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: arena.border),
            ),
            child: Column(
              children: [
                _metricRow(
                  label: 'Original Allocated Duration',
                  value: '${allocatedDuration.inMinutes} minutes',
                  arena: arena,
                ),
                Divider(height: AppSpacing.md, color: arena.border),
                _metricRow(
                  label: 'Scheduled Expiry Time',
                  value: IstTime.format12(_session.scheduledEndAt),
                  arena: arena,
                ),
                Divider(height: AppSpacing.md, color: arena.border),
                _metricRow(
                  label: 'Time Since Expiry',
                  value: '+${formatClock(timer.overtime(now))}',
                  valueColor: Red404.r400,
                  arena: arena,
                ),
                Divider(height: AppSpacing.md, color: arena.border),
                _metricRow(
                  label: 'Frozen Bill (at Cutoff)',
                  value: Paise(frozenBill.total.value).display,
                  valueColor: arena.primary,
                  isBold: true,
                  arena: arena,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Action Mode Switching ──
          if (_mode == ExpiryActionMode.overview) ...[
            Text('Select Staff Action', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),

            // Action 1: Extend Time
            Card(
              color: arena.surface,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: arena.border),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: arena.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Icon(Icons.add_alarm_rounded, color: arena.primary, size: 20),
                ),
                title: Text(
                  'Extend Time',
                  style: ArenaType.label.copyWith(color: arena.text, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Add approved minutes with previewed rate-card pricing.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  setState(() => _mode = ExpiryActionMode.extend);
                  _loadPreview();
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Action 2: Continue Session (Disabled with explanation per prompt)
            Card(
              color: arena.surfaceSunken,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: arena.border),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: arena.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Icon(Icons.play_arrow_outlined, color: arena.textMuted, size: 20),
                ),
                title: Row(
                  children: [
                    Text(
                      'Continue Session',
                      style: ArenaType.label.copyWith(color: arena.textMuted),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: arena.surfaceRaised,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'UNCONFIGURED',
                        style: ArenaType.micro.copyWith(color: arena.textMuted, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  'Open-ended post-expiry billing rule is not defined. Use structured "Extend Time" to add playtime.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                onTap: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Continuation Rule Unconfigured'),
                      content: const Text(
                        'Arena Ops enforces deterministic, pre-quoted billing to prevent unexpected customer charges. '
                        'Open-ended post-expiry playback without an explicit extension duration is not supported by the active rate card.\n\n'
                        'Please use "Extend Time" to add a specific duration (+15m, +30m, +60m) or "End Session & Bill" to check out.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Understood'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Action 3: End Session & Bill
            Card(
              color: arena.surface,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: arena.border),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x28FF3B30),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: const Icon(Icons.point_of_sale_rounded, color: Red404.r400, size: 20),
                ),
                title: Text(
                  'End Session & Bill (${Paise(frozenBill.total.value).display})',
                  style: ArenaType.label.copyWith(color: arena.text, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Conclude session now and collect payment for the agreed cutoff duration.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openingEnd ? null : _handleEndSession,
              ),
            ),
          ] else ...[
            // ── Inline Extension Configuration ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Select Extension Duration', style: theme.textTheme.labelLarge),
                TextButton(
                  onPressed: () => setState(() => _mode = ExpiryActionMode.overview),
                  child: const Text('Back to options'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Builder(builder: (context) {
              const presets = [15, 30, 60];
              final isCustom = !presets.contains(_extendMinutes);
              return Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final m in presets)
                    ChoiceChip(
                      label: Text('+$m min'),
                      selected: _extendMinutes == m,
                      onSelected: (_) {
                        setState(() => _extendMinutes = m);
                        _loadPreview();
                      },
                    ),
                  ChoiceChip(
                    label: Text(isCustom ? 'Custom · +$_extendMinutes min' : 'Custom'),
                    selected: isCustom,
                    onSelected: (_) async {
                      final mins = await showCustomMinutesSheet(
                        context,
                        initial: _extendMinutes,
                        title: 'Custom extension',
                      );
                      if (mins != null) {
                        setState(() => _extendMinutes = mins);
                        _loadPreview();
                      }
                    },
                  ),
                ],
              );
            }),
            const SizedBox(height: AppSpacing.md),

            // Plan details preview
            if (_previewLoading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_plan?.valueOrNull != null) ...[
              _ExtensionPreviewBox(
                plan: _plan!.valueOrNull!,
                arena: arena,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _applyingExtension ? null : _applyExtension,
                icon: _applyingExtension
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _applyingExtension
                      ? 'Applying Extension…'
                      : 'Confirm Extension (+${_plan!.valueOrNull!.addedCost.display})',
                ),
              ),
            ] else if (_plan?.failureOrNull != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Text(
                  _plan!.failureOrNull!.display,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _metricRow({
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
    required ArenaColors arena,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: ArenaType.caption.copyWith(color: arena.textMuted)),
        Text(
          value,
          style: AppTextStyles.mono(ArenaType.caption).copyWith(
            color: valueColor ?? arena.text,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _applyExtension() async {
    if (_applyingExtension) return; // Prevent duplicate requests
    setState(() => _applyingExtension = true);

    final actions = ref.read(sessionActionsProvider);
    final result = await actions.extend(
      _session,
      widget.active.segments,
      _extendMinutes,
    );

    if (!mounted) return;
    setState(() => _applyingExtension = false);

    result.fold(
      (_) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Session extended by $_extendMinutes min')),
        );
      },
      (f) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(f.display)),
        );
      },
    );
  }

  void _handleEndSession() {
    if (_openingEnd) return; // Debounce guard
    setState(() => _openingEnd = true);
    Navigator.of(context).pop();
    showEndSessionSheet(context, widget.active);
  }
}

class _ExtensionPreviewBox extends StatelessWidget {
  const _ExtensionPreviewBox({
    required this.plan,
    required this.arena,
  });

  final ExtensionPlan plan;
  final ArenaColors arena;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Added Duration', style: ArenaType.caption.copyWith(color: arena.textMuted)),
              Text('+${plan.addedMinutes} min', style: ArenaType.caption.copyWith(color: arena.text)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('New Scheduled End', style: ArenaType.caption.copyWith(color: arena.textMuted)),
              Text(IstTime.format12(plan.newEnd), style: ArenaType.caption.copyWith(color: arena.text)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Additional Charge', style: ArenaType.caption.copyWith(color: arena.textMuted)),
              Text(
                plan.addedCost.display,
                style: AppTextStyles.mono(ArenaType.label).copyWith(color: arena.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
