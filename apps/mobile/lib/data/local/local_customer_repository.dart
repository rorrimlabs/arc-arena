import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/mappers.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/repositories/customer_repository.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class LocalCustomerRepository implements CustomerRepository {
  LocalCustomerRepository(this._db,
      [this._clock = const SystemClock(), this._sync]);

  final AppDatabase _db;
  final Clock _clock;

  /// Cloud mode only (see SyncRecorder). Null in local-only mode.
  final SyncRecorder? _sync;

  Future<void> _insert(CustomerRow row) => _db.transaction(() async {
        await _db.into(_db.customers).insert(row);
        await _sync?.record(
          kind: 'customer.create',
          entityType: 'customer',
          entityId: row.id,
          payload: {
            'id': row.id,
            'name': row.name,
            'phone': row.phone,
            'notes': row.notes,
            'is_guest': row.isGuest,
            'birth_year': row.birthYear,
            'last_visit_at': Wire.at(row.lastVisitAt),
            'created_at': Wire.at(row.createdAt),
          },
        );
      });
  static const _uuid = Uuid();

  @override
  Stream<List<Customer>> watchRecent({int limit = 20}) {
    final q = _db.select(_db.customers)
      ..where((t) => t.isGuest.equals(false))
      ..orderBy([
        // Nulls sort last in SQLite DESC, so never-visited customers trail.
        (t) => OrderingTerm(expression: t.lastVisitAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(customerFromRow).toList());
  }

  @override
  Future<List<Customer>> all() async {
    final rows = await (_db.select(_db.customers)
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
    return rows.map(customerFromRow).toList();
  }

  @override
  Future<List<Customer>> search(String query, {int limit = 20}) async {
    final like = '%${query.trim()}%';
    final q = _db.select(_db.customers)
      ..where((t) =>
          t.isGuest.equals(false) & (t.name.like(like) | t.phone.like(like)))
      ..orderBy([(t) => OrderingTerm(expression: t.name)])
      ..limit(limit);
    final rows = await q.get();
    return rows.map(customerFromRow).toList();
  }

  @override
  Future<Customer?> getById(String id) async {
    final row = await (_db.select(_db.customers)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : customerFromRow(row);
  }

  @override
  Future<Customer?> findByPhone(String phone) async {
    final row = await (_db.select(_db.customers)
          ..where((t) => t.phone.equals(phone)))
        .getSingleOrNull();
    return row == null ? null : customerFromRow(row);
  }

  @override
  Future<Customer> create({
    required String name,
    String? phone,
    String? notes,
    int? birthYear,
  }) async {
    final now = _clock.now();
    final row = CustomerRow(
      id: _uuid.v4(),
      name: name.trim(),
      phone: phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      notes: notes,
      lastVisitAt: null,
      isGuest: false,
      birthYear: birthYear,
      createdAt: now,
      updatedAt: now,
    );
    await _insert(row);
    return customerFromRow(row);
  }

  @override
  Future<Customer> createGuest() async {
    final now = _clock.now();
    // Named with the arrival time so staff can tell two concurrent walk-ins
    // apart on the floor and in history, without asking anyone for a name.
    final row = CustomerRow(
      id: _uuid.v4(),
      name: 'Walk-in ${IstTime.format12(now)}',
      phone: null,
      notes: null,
      lastVisitAt: now,
      isGuest: true,
      createdAt: now,
      updatedAt: now,
    );
    await _insert(row);
    return customerFromRow(row);
  }

  @override
  Future<Customer> update(Customer customer) async {
    final now = _clock.now();
    await _db.transaction(() async {
      await (_db.update(_db.customers)..where((t) => t.id.equals(customer.id)))
          .write(CustomersCompanion(
        name: Value(customer.name),
        phone: Value(customer.phone),
        notes: Value(customer.notes),
        birthYear: Value(customer.birthYear),
        updatedAt: Value(now),
      ));
      await _sync?.record(
        kind: 'customer.update',
        entityType: 'customer',
        entityId: customer.id,
        payload: {
          'id': customer.id,
          'name': customer.name,
          'phone': customer.phone,
          'notes': customer.notes,
          'birth_year': customer.birthYear,
          'base_version': await _sync.baseVersion('customers', customer.id),
        },
      );
    });
    return (await getById(customer.id))!;
  }

  @override
  Future<void> touchVisit(String id, DateTime at) async {
    await (_db.update(_db.customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(lastVisitAt: Value(at.toUtc()), updatedAt: Value(at.toUtc())),
    );
  }
}
