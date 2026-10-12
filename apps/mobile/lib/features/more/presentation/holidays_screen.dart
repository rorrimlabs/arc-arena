import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Public holidays and one-off closures (brief §8).
///
/// A holiday suspends **happy hour** for that date. Whether the arena also
/// shuts is a separate switch, because the rate rules only ever said happy
/// hour is excluded — see OWNER CONFIRMATION #26.
class HolidaysScreen extends ConsumerStatefulWidget {
  const HolidaysScreen({super.key});

  static const String path = '/settings/holidays';

  @override
  ConsumerState<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends ConsumerState<HolidaysScreen> {
  List<Holiday> _holidays = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(catalogRepositoryProvider).holidays();
    if (mounted) {
      setState(() {
        _holidays = rows;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;

    return Scaffold(
      appBar: AppBar(title: const Text('Holidays')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add holiday'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
              children: [
                Text(
                  'Happy-hour pricing never applies on these dates. Tick '
                  '"closed" as well if the arena does not open at all.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_holidays.isEmpty)
                  Text('No holidays configured.',
                      style: ArenaType.body.copyWith(color: arena.textMuted)),
                for (final h in _holidays)
                  Dismissible(
                    key: ValueKey(h.day.iso),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: AppSpacing.lg),
                      color: arena.danger,
                      child: const Icon(Icons.delete_outline),
                    ),
                    onDismissed: (_) => _delete(h),
                    child: ListTile(
                      title: Text(h.name),
                      subtitle: Text(
                        '${h.day.iso}'
                        '${h.closed ? ' · closed all day' : ' · open, no happy hour'}',
                      ),
                      trailing: Switch(
                        value: h.closed,
                        onChanged: (v) => _save(
                          (day: h.day, name: h.name, closed: v),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _add() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'Holiday date',
    );
    if (date == null || !mounted) return;

    final result = await showDialog<({String name, bool closed})>(
      context: context,
      builder: (_) => const _AddHolidayDialog(),
    );
    if (result == null || result.name.isEmpty) return;
    final name = result.name;
    final closed = result.closed;
    await _save((
      day: IstDate(date.year, date.month, date.day),
      name: name,
      closed: closed,
    ));
  }

  Future<void> _save(Holiday holiday) async {
    await ref.read(catalogRepositoryProvider).upsertHoliday(holiday);
    ref.invalidate(pricingSnapshotProvider);
    await _load();
  }

  Future<void> _delete(Holiday holiday) async {
    await ref.read(catalogRepositoryProvider).deleteHoliday(holiday.day);
    ref.invalidate(pricingSnapshotProvider);
    await _load();
  }
}

/// Owns its text controller so nothing disposes it while the route is still
/// animating out.
class _AddHolidayDialog extends StatefulWidget {
  const _AddHolidayDialog();

  @override
  State<_AddHolidayDialog> createState() => _AddHolidayDialogState();
}

class _AddHolidayDialogState extends State<_AddHolidayDialog> {
  final _name = TextEditingController();
  bool _closed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add holiday'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Diwali',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Closed all day'),
            value: _closed,
            onChanged: (v) => setState(() => _closed = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop((name: _name.text.trim(), closed: _closed)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
