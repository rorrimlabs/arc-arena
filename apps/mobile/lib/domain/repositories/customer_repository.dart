import 'package:arena_ops/domain/entities/customer.dart';

abstract interface class CustomerRepository {
  /// Most recently active customers first (spec §10 recent customers).
  /// Walk-ins are excluded — they are visits, not members.
  Stream<List<Customer>> watchRecent({int limit});

  /// Search by name or phone (spec §21).
  Future<List<Customer>> search(String query, {int limit});

  Future<Customer?> getById(String id);

  /// Every customer — used to resolve names and count new sign-ups in reports.
  Future<List<Customer>> all();

  /// Used to prevent duplicate phone numbers within the arena (spec §21, §32).
  Future<Customer?> findByPhone(String phone);

  Future<Customer> create({required String name, String? phone, String? notes, int? birthYear});

  /// A one-tap walk-in: a record per visit so the session can be billed and
  /// counted, with no details asked for (brief §4, §12).
  Future<Customer> createGuest();

  Future<Customer> update(Customer customer);

  /// Stamps lastVisitAt (called when a session starts).
  Future<void> touchVisit(String id, DateTime at);
}
