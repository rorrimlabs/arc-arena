import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create a customer with a duplicate-phone guard (spec §21, §41). Returns the
/// created (or matched-existing) customer, or null if cancelled.
Future<Customer?> showCreateCustomerDialog(
  BuildContext context,
  WidgetRef ref, {
  String? initialName,
}) {
  final nameCtrl = TextEditingController(text: initialName ?? '');
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
                      FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: Text('Use ${existing.name}'),
                      ),
                    ],
                  ),
                );
                if (use == true && ctx.mounted) Navigator.pop(ctx, existing);
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
