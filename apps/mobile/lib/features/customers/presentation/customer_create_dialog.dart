import 'package:arena_ops/app/controllers/customer_actions.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create a customer with a duplicate-phone guard (spec §21, §41). Returns the
/// created (or matched-existing) customer, or null if cancelled.
///
/// The write goes through [CustomerActions], which checks the signed-in
/// user may add customers and re-checks the name, birth year and phone.
Future<Customer?> showCreateCustomerDialog(
  BuildContext context,
  WidgetRef ref, {
  String? initialName,
}) {
  final nameCtrl = TextEditingController(text: initialName ?? '');
  final phoneCtrl = TextEditingController();
  final yearCtrl = TextEditingController();
  final actions = ref.read(customerActionsProvider);
  final thisYear = actions.currentYear;
  String? yearError;
  var saving = false;

  return showDialog<Customer>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
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
            TextField(
              controller: yearCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'Birth year (optional)',
                helperText: 'For age-rated games',
                counterText: '',
                errorText: yearError,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final yearProblem =
                        Customer.birthYearError(yearCtrl.text, thisYear);
                    if (yearProblem != null) {
                      setLocal(() => yearError = yearProblem);
                      return;
                    }
                    final phone = phoneCtrl.text.trim();
                    if (phone.isNotEmpty) {
                      final existing = await actions.findByPhone(phone);
                      if (existing != null && ctx.mounted) {
                        final use = await showDialog<bool>(
                          context: ctx,
                          builder: (d) => AlertDialog(
                            content: Text(
                              '${existing.name} already uses this phone '
                              'number. Use ${existing.name}?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('No'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: Text('Use ${existing.name}'),
                              ),
                            ],
                          ),
                        );
                        if (use == true && ctx.mounted) {
                          Navigator.pop(ctx, existing);
                        }
                        return;
                      }
                    }
                    setLocal(() => saving = true);
                    final created = await actions.create(
                      name: name,
                      phone: phone.isEmpty ? null : phone,
                      birthYear: int.tryParse(yearCtrl.text.trim()),
                    );
                    if (!ctx.mounted) return;
                    created.fold(
                      (c) => Navigator.pop(ctx, c),
                      (f) {
                        setLocal(() => saving = false);
                        ScaffoldMessenger.of(ctx)
                            .showSnackBar(SnackBar(content: Text(f.display)));
                      },
                    );
                  },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}
