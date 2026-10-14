import 'package:arena_ops/app/controllers/catalog_actions.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/business_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opening hours per weekday (brief §8).
///
/// These drive booking availability, the close time and the utilisation
/// denominator in reports, so they are stored, not compiled in. The seeded
/// default is **open Tue–Sun 2–11 PM (Monday closed)** — change it here if the
/// arena's trading days differ. Time-of-day prices are pricing rules, set on
/// the dashboard.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key});

  static const String path = '/settings/hours';

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  BusinessHours? _hours;
  bool _dirty = false;
  bool _saving = false;

  static const _weekdayNames = {
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hours = await ref.read(catalogRepositoryProvider).businessHours();
    if (mounted) setState(() => _hours = hours);
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final hours = _hours;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opening hours'),
        actions: [
          TextButton(
            onPressed: _dirty && !_saving ? _save : null,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: hours == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  'A day with no opening window is closed.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final day in _weekdayNames.keys)
                  _DayRow(
                    label: _weekdayNames[day]!,
                    open: hours.openByWeekday[day],
                    onChanged: (open) => setState(() {
                      _hours = BusinessHours(
                        openByWeekday: {...hours.openByWeekday, day: open},
                      );
                      _dirty = true;
                    }),
                  ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await ref.read(catalogActionsProvider).saveBusinessHours(_hours!);
    if (r.isErr) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.failureOrNull!.display)),
      );
      return;
    }
    // The snapshot carries the hours, so anything pricing or planning a new
    // session must pick them up.
    ref.invalidate(pricingSnapshotProvider);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Opening hours saved. Sessions already running keep the hours they '
          'started under.',
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.open,
    required this.onChanged,
  });

  final String label;
  final DayWindow? open;
  final void Function(DayWindow? open) onChanged;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final isOpen = open != null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
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
              Expanded(
                child: Text(label,
                    style: ArenaType.label.copyWith(color: arena.text)),
              ),
              Text(isOpen ? 'Open' : 'Closed',
                  style: ArenaType.caption.copyWith(
                    color: isOpen ? arena.primary : arena.textSubtle,
                  )),
              Switch(
                value: isOpen,
                onChanged: (on) => onChanged(
                  on ? const DayWindow.hm(14, 0, 23, 0) : null,
                ),
              ),
            ],
          ),
          if (isOpen)
            _TimeRow(
              caption: 'Opening',
              window: open!,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.caption,
    required this.window,
    required this.onChanged,
  });

  final String caption;
  final DayWindow window;
  final ValueChanged<DayWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;

    Future<void> pick({required bool isStart}) async {
      final minutes = isStart ? window.startMinute : window.endMinute;
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        helpText: isStart ? '$caption starts' : '$caption ends',
      );
      if (picked == null) return;
      final asMinutes = picked.hour * 60 + picked.minute;
      final start = isStart ? asMinutes : window.startMinute;
      final end = isStart ? window.endMinute : asMinutes;
      // A window must be a real span; ignore an inverted pick rather than
      // storing something the calendar would reject.
      if (start >= end) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The end time must be after the start.')),
          );
        }
        return;
      }
      onChanged(DayWindow(start, end));
    }

    String fmt(int minutes) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
    }

    return Row(
      children: [
        Text(caption, style: ArenaType.caption.copyWith(color: arena.textMuted)),
        const Spacer(),
        TextButton(
          onPressed: () => pick(isStart: true),
          child: Text(fmt(window.startMinute)),
        ),
        Text('–', style: ArenaType.caption.copyWith(color: arena.textSubtle)),
        TextButton(
          onPressed: () => pick(isStart: false),
          child: Text(fmt(window.endMinute)),
        ),
      ],
    );
  }
}
