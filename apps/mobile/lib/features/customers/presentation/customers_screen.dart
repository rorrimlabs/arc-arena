import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/features/customers/presentation/customer_create_dialog.dart';
import 'package:arena_ops/features/customers/presentation/customer_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  static const String path = '/customers';

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';
  List<Customer> _results = const [];

  Future<void> _search(String q) async {
    setState(() => _query = q);
    if (q.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final r = await ref.read(customerRepositoryProvider).search(q);
    if (mounted) setState(() => _results = r);
  }

  void _open(Customer c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomerProfileScreen(customerId: c.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(recentCustomersProvider).value ?? const [];
    final list = _query.trim().isEmpty ? recent : _results;

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showCreateCustomerDialog(context, ref);
          if (created != null && context.mounted) _open(created);
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name or phone',
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          if (_query.trim().isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text('Recent'),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      _query.trim().isEmpty
                          ? 'No customers yet. Tap New to add one.'
                          : 'No matches for "$_query".',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(c.name),
                        subtitle: c.phone == null ? null : Text(c.phone!),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
