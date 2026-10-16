/// Application-layer customer (member) writes: register, quick walk-in, edit.
///
/// Whoever runs the floor (`start`) or manages members (`members`) may do
/// these — the rule the server's customer.create / customer.update apply. The
/// check lives here, underneath every dialog that adds or edits a customer.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/monitoring/app_telemetry.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/repositories/customer_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomerActions {
  CustomerActions({
    required this.customers,
    required this.clock,
    this.guard = const PermissionGuard(null),
  });

  final CustomerRepository customers;
  final Clock clock;

  /// Who is signed in. Defaults to "nobody", so a caller that forgets to pass
  /// it is refused rather than quietly allowed.
  final PermissionGuard guard;

  static const _allowed = [Permission.start, Permission.members];

  /// For deciding what to *show*; every write checks again.
  bool get canManageCustomers => guard.allowsAny(_allowed);

  /// The current IST year — the upper bound for a birth year.
  int get currentYear => IstDate.fromUtc(clock.now()).year;

  /// The customer already using [phone], if any (the duplicate-phone guard,
  /// spec §21, §41). A read: lets a dialog offer "use them instead?".
  Future<Customer?> findByPhone(String phone) =>
      customers.findByPhone(phone.trim());

  Future<Failure?> _problems({
    required String name,
    required String? phone,
    required int? birthYear,
    String? exceptId,
  }) async {
    if (name.trim().isEmpty) {
      return const Failure(
        message: 'The customer needs a name.',
        fix: 'Type their name, or start a walk-in without details.',
        code: 'name_required',
      );
    }
    if (birthYear != null) {
      final error = Customer.birthYearError('$birthYear', currentYear);
      if (error != null) {
        return Failure(message: '$error.', code: 'invalid_birth_year');
      }
    }
    final p = phone?.trim() ?? '';
    if (p.isNotEmpty) {
      final existing = await customers.findByPhone(p);
      if (existing != null && existing.id != exceptId) {
        return Failure(
          message: '${existing.name} already uses this phone number.',
          fix: 'Pick ${existing.name} instead, or use another number.',
          code: 'duplicate_phone',
        );
      }
    }
    return null;
  }

  /// Register a customer. Refuses a phone number someone else already uses.
  Future<Result<Customer>> create({
    required String name,
    String? phone,
    int? birthYear,
    String? notes,
  }) async {
    final denied = guard.checkAny(_allowed);
    if (denied != null) return Err(denied);
    final problem = await _problems(
      name: name,
      phone: phone,
      birthYear: birthYear,
    );
    if (problem != null) return Err(problem);
    final p = phone?.trim() ?? '';
    final created = await customers.create(
      name: name.trim(),
      phone: p.isEmpty ? null : p,
      birthYear: birthYear,
      notes: notes,
    );
    AppTelemetry.addBreadcrumb(
      category: 'customer',
      message: 'customer_created',
      data: {'customerId': created.id},
    );
    return Ok(created);
  }

  /// A one-tap walk-in: billed and counted like anyone, no details asked.
  Future<Result<Customer>> createGuest() async {
    final denied = guard.checkAny(_allowed);
    if (denied != null) return Err(denied);
    final guest = await customers.createGuest();
    AppTelemetry.addBreadcrumb(
      category: 'customer',
      message: 'guest_created',
      data: {'customerId': guest.id},
    );
    return Ok(guest);
  }

  /// Edit a customer's name, phone, birth year or notes.
  Future<Result<Customer>> update(Customer customer) async {
    final denied = guard.checkAny(_allowed);
    if (denied != null) return Err(denied);
    final problem = await _problems(
      name: customer.name,
      phone: customer.phone,
      birthYear: customer.birthYear,
      exceptId: customer.id,
    );
    if (problem != null) return Err(problem);
    final p = customer.phone?.trim() ?? '';
    final updated = await customers.update(
      customer.copyWith(
        name: customer.name.trim(),
        phone: p.isEmpty ? null : p,
      ),
    );
    AppTelemetry.addBreadcrumb(
      category: 'customer',
      message: 'customer_updated',
      data: {'customerId': updated.id},
    );
    return Ok(updated);
  }
}

final customerActionsProvider = Provider<CustomerActions>(
  (ref) => CustomerActions(
    customers: ref.watch(customerRepositoryProvider),
    clock: ref.watch(clockProvider),
    guard: PermissionGuard(ref.watch(authControllerProvider)),
  ),
);
