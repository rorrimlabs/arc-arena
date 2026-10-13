import 'package:arena_ops/app/controllers/catalog_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/money/paise.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_header.dart';
import 'package:arena_ops/domain/pricing/billing_policy.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The billing rules the owner has to confirm (OWNER CONFIRMATION #1–#24).
///
/// Each one ships with a documented, conservative default so the engine is
/// usable from day one, and each is editable here rather than buried in code.
/// Changing a rule affects **new** sessions only — a session carries the rules
/// it started under in its pricing snapshot.
class BillingRulesScreen extends ConsumerStatefulWidget {
  const BillingRulesScreen({super.key});

  static const String path = '/settings/billing-rules';

  @override
  ConsumerState<BillingRulesScreen> createState() => _BillingRulesScreenState();
}

class _BillingRulesScreenState extends ConsumerState<BillingRulesScreen> {
  BillingPolicy? _policy;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await ref.read(catalogRepositoryProvider).policy();
    if (mounted) setState(() => _policy = p);
  }

  void _update(BillingPolicy next) => setState(() {
        _policy = next;
        _dirty = true;
      });

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final p = _policy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing rules'),
        actions: [
          TextButton(
            onPressed: _dirty && !_saving ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'These are the rules the price list does not state. The '
                    'values below are safe defaults, not decisions — confirm '
                    'them with the owner. Changes apply to new sessions only.',
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                ),
                const ArenaSectionLabel(label: 'Time'),
                _Choice<BillingUnit>(
                  title: 'Charge partial time',
                  subtitle: 'How a part-hour becomes money',
                  value: p.billingUnit,
                  options: {
                    BillingUnit.perMinute: 'Per minute (exact)',
                    BillingUnit.block15: 'In 15-minute blocks',
                    BillingUnit.block30: 'In 30-minute blocks',
                    BillingUnit.block60: 'In whole hours',
                  },
                  onChanged: (v) => _update(p.copyWith(billingUnit: v)),
                ),
                if (p.billingUnit != BillingUnit.perMinute)
                  _Choice<Rounding>(
                    title: 'Block rounding',
                    subtitle: 'When time falls mid-block',
                    value: p.blockRounding,
                    options: const {
                      Rounding.up: 'Always round up',
                      Rounding.nearest: 'Round to nearest',
                    },
                    onChanged: (v) => _update(p.copyWith(blockRounding: v)),
                  ),
                _Minutes(
                  title: 'Grace period',
                  subtitle: 'Under this, the session is free',
                  value: p.graceMinutes,
                  onChanged: (v) => _update(p.copyWith(graceMinutes: v)),
                ),
                _Minutes(
                  title: 'Minimum charge',
                  subtitle: 'Shortest billable session',
                  value: p.minimumChargeMinutes,
                  onChanged: (v) =>
                      _update(p.copyWith(minimumChargeMinutes: v)),
                ),
                _Choice<EarlyExit>(
                  title: 'If they leave early',
                  value: p.earlyExit,
                  options: const {
                    EarlyExit.actual: 'Bill the time actually played',
                    EarlyExit.planned: 'Bill the full booked duration',
                  },
                  onChanged: (v) => _update(p.copyWith(earlyExit: v)),
                ),
                const ArenaSectionLabel(label: 'Money'),
                _Choice<int>(
                  title: 'Round the final bill to',
                  value: p.moneyRoundingPaise,
                  options: const {
                    100: 'Nearest ₹1',
                    500: 'Nearest ₹5',
                    1000: 'Nearest ₹10',
                  },
                  onChanged: (v) => _update(p.copyWith(moneyRoundingPaise: v)),
                ),
                _Choice<MoneyRoundingDir>(
                  title: 'Rounding direction',
                  value: p.moneyRoundingDir,
                  options: const {
                    MoneyRoundingDir.nearest: 'To the nearest',
                    MoneyRoundingDir.up: 'Always up',
                  },
                  onChanged: (v) => _update(p.copyWith(moneyRoundingDir: v)),
                ),
                _Choice<RoundingScope>(
                  title: 'Round once or per segment',
                  subtitle:
                      'A session that switched station has several segments',
                  value: p.roundingScope,
                  options: const {
                    RoundingScope.session: 'Once, on the session total',
                    RoundingScope.segment: 'Separately for each segment',
                  },
                  onChanged: (v) => _update(p.copyWith(roundingScope: v)),
                ),
                const ArenaSectionLabel(label: 'VR'),
                _Choice<VrUnitRounding>(
                  title: 'Part-used VR block',
                  subtitle: 'VR sells in fixed blocks',
                  value: p.vrUnitRounding,
                  options: const {
                    VrUnitRounding.up: 'Charge the whole block',
                    VrUnitRounding.nearest: 'Round to the nearest block',
                    VrUnitRounding.prorate: 'Charge the exact time used',
                  },
                  onChanged: (v) => _update(p.copyWith(vrUnitRounding: v)),
                ),
                const ArenaSectionLabel(label: 'Groups'),
                _Choice<GroupBillingMode>(
                  title: 'Group across several systems',
                  subtitle:
                      'Three controllers does not automatically buy three systems',
                  value: p.groupBillingMode,
                  options: const {
                    GroupBillingMode.perSystem:
                        'Each system billed for its own controllers',
                    GroupBillingMode.sharedControllerPool:
                        'Pay once for the controllers bought',
                  },
                  onChanged: (v) => _update(p.copyWith(groupBillingMode: v)),
                ),
                const ArenaSectionLabel(label: 'Floor'),
                SwitchListTile(
                  title: const Text('Allow extending past closing time'),
                  subtitle: const Text('Off: an extension stops at closing'),
                  value: p.allowExtendPastClose,
                  onChanged: (v) =>
                      _update(p.copyWith(allowExtendPastClose: v)),
                ),
                _Minutes(
                  title: 'Cleaning gap between sessions',
                  subtitle: 'Held free after a session ends',
                  value: p.cleaningGapMinutes,
                  onChanged: (v) => _update(p.copyWith(cleaningGapMinutes: v)),
                ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await ref.read(catalogActionsProvider).savePolicy(_policy!);
    if (r.isErr) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.failureOrNull!.display)),
      );
      return;
    }
    ref.invalidate(pricingSnapshotProvider);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Billing rules saved for new sessions.')),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text([?subtitle, options[value] ?? '—'].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final e in options.entries)
                  ListTile(
                    title: Text(e.value),
                    trailing: e.key == value
                        ? Icon(Icons.check, color: context.arena.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(e.key),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _Minutes extends StatelessWidget {
  const _Minutes({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(
        [?subtitle, value == 0 ? 'None' : '$value min'].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final picked = await showModalBottomSheet<int>(
          context: context,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final m in const [0, 5, 10, 15, 30, 60])
                  ListTile(
                    title: Text(m == 0 ? 'None' : '$m minutes'),
                    trailing: m == value
                        ? Icon(Icons.check, color: context.arena.primary)
                        : null,
                    onTap: () => Navigator.of(context).pop(m),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Exposed for the settings subtitle so the hub can show the live money rule.
String moneyRoundingLabel(BillingPolicy p) =>
    'Bills rounded ${p.moneyRoundingDir == MoneyRoundingDir.up ? 'up' : 'to nearest'} '
    '${Paise(p.moneyRoundingPaise).display}';
