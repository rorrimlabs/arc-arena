import 'package:arena_ops/app/controllers/catalog_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/money/rupee_input.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/core/time/duration_format.dart';
import 'package:arena_ops/domain/entities/activity.dart';
import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/features/more/presentation/hours_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The rate card — the single place prices are defined (brief §8).
///
/// Every figure shown here is read from the stored rate rows, so the screen
/// cannot drift from what the pricing engine charges. Editing a rate affects
/// **new** sessions only: a session captures an immutable pricing snapshot
/// when it starts, so bills already issued never move.
class PricingScreen extends ConsumerWidget {
  const PricingScreen({super.key});

  static const String path = '/settings/pricing';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final snapshotAsync = ref.watch(pricingSnapshotProvider);
    final activitiesAsync = ref.watch(activitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pricing & price bands')),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text('Could not load pricing: $err',
                style: TextStyle(color: arena.danger)),
          ),
        ),
        data: (snapshot) {
          final activities = activitiesAsync.value ?? const <Activity>[];
          final rates = snapshot.rates;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x5,
              AppSpacing.lg,
              AppSpacing.x5,
              AppSpacing.xxl,
            ),
            children: [
              _TradingHoursBanner(hours: snapshot.hours),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Tap any rate to change it. New prices apply to sessions '
                'started afterwards; bills already issued keep the price they '
                'were quoted.',
                style: ArenaType.caption.copyWith(color: arena.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final activity in activities) ...[
                ArenaSectionLabel(label: activity.name.toUpperCase()),
                _ActivityRates(
                  activity: activity,
                  rates: rates,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ActivityRates extends ConsumerWidget {
  const _ActivityRates({required this.activity, required this.rates});

  final Activity activity;
  final List<Rate> rates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Rate? find(Band band, int? controllers) {
      for (final r in rates) {
        if (r.activityCode == activity.code &&
            r.band == band &&
            r.controllerCount == controllers) {
          return r;
        }
      }
      return null;
    }

    // A controller-based activity has one row per controller count; everything
    // else has a single row.
    final counts = activity.usesControllers ? const [1, 2, 3, 4] : const [null];

    return Column(
      children: [
        for (final c in counts)
          _RateRow(
            label: c == null
                ? activity.name
                : '$c controller${c == 1 ? '' : 's'}',
            standard: find(Band.standard, c),
            onEdit: (band) => _edit(context, ref, band, c, find(band, c)),
          ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Band band,
    int? controllers,
    Rate? existing,
  ) async {
    final unitMinutes = existing?.unitMinutes ??
        rates
            .firstWhere(
              (r) => r.activityCode == activity.code,
              orElse: () => Rate(
                activityCode: activity.code,
                band: band,
                controllerCount: controllers,
                unitMinutes: 60,
                price: Paise.zero,
              ),
            )
            .unitMinutes;

    final result = await showModalBottomSheet<({int paise, int unit})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RateEditor(
        title: activity.name,
        subtitle: [
          'Standard',
          if (controllers != null)
            '$controllers controller${controllers == 1 ? '' : 's'}',
        ].join(' · '),
        initialPaise: existing?.price.value ?? 0,
        initialUnitMinutes: unitMinutes,
      ),
    );
    if (result == null) return;

    final r = await ref.read(catalogActionsProvider).saveRate(
          Rate(
            activityCode: activity.code,
            band: band,
            controllerCount: controllers,
            unitMinutes: result.unit,
            price: Paise(result.paise),
          ),
        );
    if (r.isOk) ref.invalidate(pricingSnapshotProvider);
    if (context.mounted) {
      showResult(context, r, '${activity.name} rate saved — applies to new sessions.');
    }
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.label,
    required this.standard,
    required this.onEdit,
  });

  final String label;
  final Rate? standard;
  final ValueChanged<Band> onEdit;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;

    Widget cell(Band band, Rate? rate, Color color) {
      final unit = rate == null
          ? ''
          : '/${formatPerUnit(rate.unitMinutes)}';
      return Expanded(
        child: InkWell(
          onTap: () => onEdit(band),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Standard',
                  style: ArenaType.caption.copyWith(color: arena.textSubtle),
                ),
                Text(
                  rate == null ? 'Not set' : '${rate.price.display}$unit',
                  style: AppTextStyles.mono(ArenaType.label).copyWith(
                    color: rate == null ? arena.textSubtle : color,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: ArenaType.body.copyWith(color: arena.text)),
          ),
          cell(Band.standard, standard, arena.text),
        ],
      ),
    );
  }
}

class _RateEditor extends StatefulWidget {
  const _RateEditor({
    required this.title,
    required this.subtitle,
    required this.initialPaise,
    required this.initialUnitMinutes,
  });

  final String title;
  final String subtitle;
  final int initialPaise;
  final int initialUnitMinutes;

  @override
  State<_RateEditor> createState() => _RateEditorState();
}

class _RateEditorState extends State<_RateEditor> {
  late final TextEditingController _price = TextEditingController(
    text: paiseToRupeeInput(widget.initialPaise),
  );
  late int _unit = widget.initialUnitMinutes;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  /// Exact paise for what is typed (never via a double); null when the text
  /// is not a rupee amount.
  int? get _parsed => parseRupeesToPaise(_price.text);
  int get _paise => _parsed ?? 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            Text(widget.subtitle,
                style: ArenaType.caption
                    .copyWith(color: context.arena.textMuted)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Price',
                prefixText: '₹ ',
                border: const OutlineInputBorder(),
                errorText: _price.text.trim().isNotEmpty && _parsed == null
                    ? rupeeInputError
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Charged per', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in const [15, 30, 60])
                  ChoiceChip(
                    label: Text(m == 60 ? 'hour' : '$m min'),
                    selected: _unit == m,
                    onSelected: (_) => setState(() => _unit = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _paise <= 0
                  ? null
                  : () => Navigator.of(context).pop((paise: _paise, unit: _unit)),
              child: const Text('Save rate'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reads the trading days out of the configured hours, so it can never claim
/// a schedule the app is not using.
class _TradingHoursBanner extends StatelessWidget {
  const _TradingHoursBanner({required this.hours});

  final BusinessHours hours;

  static const _short = {
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final openDays = [
      for (final e in _short.entries)
        if (hours.openByWeekday[e.key] != null) e.value,
    ];
    final openSample = hours.openByWeekday.values.firstWhere(
      (w) => w != null,
      orElse: () => null,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: arena.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: arena.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: arena.primary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('When the arena trades',
                    style: ArenaType.h3.copyWith(color: arena.text)),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HoursScreen()),
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            openDays.isEmpty
                ? 'No opening days configured.'
                : 'Open ${openDays.join(', ')}'
                    '${openSample == null ? '' : ' · ${_fmt(openSample.startMinute)} – ${_fmt(openSample.endMinute)}'}',
            style: ArenaType.body.copyWith(color: arena.text),
          ),
        ],
      ),
    );
  }
}
