/// Adding or editing a customer is allowed to whoever runs the floor (`start`)
/// or manages members (`members`) — the server's customer.create / update
/// rule. [CustomerActions] applies it underneath every dialog.
library;

import 'package:arena_ops/app/controllers/customer_actions.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/local_customer_repository.dart';
import 'package:arena_ops/data/local/seed_data.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/domain/auth/permission_guard.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pricing_fixtures.dart';

void main() {
  late AppDatabase db;
  late LocalCustomerRepository customers;
  final clock = FakeClock(ist(2026, 10, 2, 18, 0));

  const floor = AppUser(id: 'f', name: 'Priya', perms: {Permission.start});
  const membersDesk = AppUser(
    id: 'm',
    name: 'Meera',
    perms: {Permission.members},
  );
  const till = AppUser(id: 't', name: 'Sam', perms: {Permission.bill});

  CustomerActions actionsFor(AppUser? user) => CustomerActions(
    customers: customers,
    clock: clock,
    guard: PermissionGuard(user),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await LocalSeed.apply(db);
    customers = LocalCustomerRepository(db, clock);
  });

  tearDown(() async => db.close());

  group('registering a customer', () {
    for (final user in const [floor, membersDesk]) {
      test('${user.name} (${user.perms.single.code}) can', () async {
        final r = await actionsFor(user)
            .create(name: '  Rahul ', phone: ' 9000000001 ', birthYear: 2001);
        expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
        final c = r.valueOrNull!;
        expect(c.name, 'Rahul');
        expect(c.phone, '9000000001');
        expect(c.birthYear, 2001);
        expect(await customers.all(), hasLength(1));
      });
    }

    test('someone with neither start nor members is refused', () async {
      final r = await actionsFor(till).create(name: 'Rahul');
      expect(r.failureOrNull?.code, 'not_permitted');
      expect(r.failureOrNull!.message, contains('Sam'));
      expect(r.failureOrNull!.message, contains('manage members'));
      expect(await customers.all(), isEmpty);
    });

    test('nobody signed in is refused', () async {
      final r = await actionsFor(null).create(name: 'Rahul');
      expect(r.failureOrNull?.code, 'not_signed_in');
      expect(await customers.all(), isEmpty);
    });

    test('a phone someone already uses is refused', () async {
      await actionsFor(floor).create(name: 'Rahul', phone: '9000000001');
      final r = await actionsFor(floor)
          .create(name: 'Other', phone: '9000000001');
      expect(r.failureOrNull?.code, 'duplicate_phone');
      expect(r.failureOrNull!.message, contains('Rahul'));
      expect(await customers.all(), hasLength(1));
    });

    test('a blank name or an impossible birth year is refused', () async {
      expect(
        (await actionsFor(floor).create(name: '  ')).failureOrNull?.code,
        'name_required',
      );
      // The clock says 2026, so 2027 has not happened yet.
      expect(
        (await actionsFor(
          floor,
        ).create(name: 'Kid', birthYear: 2027)).failureOrNull?.code,
        'invalid_birth_year',
      );
      expect(await customers.all(), isEmpty);
    });

    test('the current year comes from the app clock', () {
      expect(actionsFor(floor).currentYear, 2026);
    });
  });

  group('a walk-in', () {
    test('someone with start can start one without details', () async {
      final r = await actionsFor(floor).createGuest();
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      expect(r.valueOrNull!.isGuest, isTrue);
    });

    test('someone without start or members is refused', () async {
      final r = await actionsFor(till).createGuest();
      expect(r.failureOrNull?.code, 'not_permitted');
      expect(await db.select(db.customers).get(), isEmpty);
    });
  });

  group('editing a customer', () {
    test('members can edit; the change is stored', () async {
      final c = (await actionsFor(floor).create(name: 'Rahul')).valueOrNull!;
      final r = await actionsFor(membersDesk)
          .update(c.copyWith(name: 'Rahul K', phone: '9000000002'));
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
      expect((await customers.getById(c.id))!.name, 'Rahul K');
    });

    test(
      'someone without start or members is refused; nothing changes',
      () async {
        final c = (await actionsFor(floor).create(name: 'Rahul')).valueOrNull!;
        final r = await actionsFor(till).update(c.copyWith(name: 'Hacked'));
        expect(r.failureOrNull?.code, 'not_permitted');
        expect((await customers.getById(c.id))!.name, 'Rahul');
      },
    );

    test('keeping their own phone is not a duplicate', () async {
      final c = (await actionsFor(
        floor,
      ).create(name: 'Rahul', phone: '9000000001')).valueOrNull!;
      final r = await actionsFor(floor).update(c.copyWith(notes: 'regular'));
      expect(r.isOk, isTrue, reason: r.failureOrNull?.display);
    });
  });
}
