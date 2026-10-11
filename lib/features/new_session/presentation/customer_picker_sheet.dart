import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Search / recent / create customer (spec §10). Returns the chosen [Customer].
Future<Customer?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: _CustomerPicker(),
    ),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  String _query = '';
  List<Customer> _results = const [];
  bool _searching = false;

  Future<void> _search(String q) async {
    setState(() => _query = q);
    if (q.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    final r = await ref.read(customerRepositoryProvider).search(q);
    if (mounted) {
      setState(() {
        _results = r;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentCustomersProvider).value ?? const [];
    final list = _query.trim().isEmpty ? recent : _results;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Customer', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          // The fastest path on a busy floor: no name, no phone, no typing.
          // The visit is still recorded and billed like any other.
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: () async {
                final guest =
                    await ref.read(customerRepositoryProvider).createGuest();
                if (context.mounted) Navigator.of(context).pop(guest);
              },
              icon: const Icon(Icons.bolt),
              label: const Text('Walk-in — start without details'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            autofocus: false,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name or phone',
              border: OutlineInputBorder(),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final created = await _createDialog(context);
              if (created != null && context.mounted) {
                Navigator.of(context).pop(created);
              }
            },
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Register a new customer'),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_query.trim().isEmpty)
            Text('Recent', style: Theme.of(context).textTheme.labelLarge),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(c.name),
                        subtitle: c.phone == null ? null : Text(c.phone!),
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<Customer?> _createDialog(BuildContext context) async {
    final nameCtrl = TextEditingController(text: _query.trim());
    final phoneCtrl = TextEditingController();
    final repo = ref.read(customerRepositoryProvider);

    return showDialog<Customer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final phone = phoneCtrl.text.trim();
              // Duplicate phone guard (spec §41).
              if (phone.isNotEmpty) {
                final existing = await repo.findByPhone(phone);
                if (existing != null && ctx.mounted) {
                  final use = await showDialog<bool>(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      content: Text(
                        '${existing.name} already uses this phone number. '
                        'Use ${existing.name}?',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
                        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Use ${existing.name}')),
                      ],
                    ),
                  );
                  if (use == true && ctx.mounted) {
                    Navigator.pop(ctx, existing);
                  }
                  return;
                }
              }
              final created = await repo.create(
                name: name,
                phone: phone.isEmpty ? null : phone,
              );
              if (ctx.mounted) Navigator.pop(ctx, created);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
