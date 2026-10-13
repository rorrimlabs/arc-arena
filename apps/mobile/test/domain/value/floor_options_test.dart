import 'package:arena_ops/domain/entities/customer.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:arena_ops/domain/value/floor_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FloorOptions', () {
    test('reads the synced setting', () {
      final o = FloorOptions.fromJson({
        'payment_methods': ['upi', 'cash'],
        'start_presets': [90, 30, 60],
        'warn_minutes': 10,
      });
      // App order for methods, ascending presets.
      expect(o.paymentMethods, [PaymentMethod.cash, PaymentMethod.upi]);
      expect(o.startPresets, [30, 60, 90]);
      expect(o.warnThreshold, const Duration(minutes: 10));
    });

    test('a method a newer server knows is skipped, not a crash', () {
      final o = FloorOptions.fromJson({
        'payment_methods': ['upi', 'wallet'],
        'start_presets': [60],
        'warn_minutes': 5,
      });
      expect(o.paymentMethods, [PaymentMethod.upi]);
    });

    test('missing or unusable values fall back to today\'s behaviour', () {
      final o = FloorOptions.fromJson({
        'payment_methods': [],
        'start_presets': [1, 9999],
        'warn_minutes': 90,
      });
      expect(o, FloorOptions.defaults);
      expect(FloorOptions.fromJson({}), FloorOptions.defaults);
    });

    test(
      'a pick that is no longer offered falls back to the first offered method',
      () {
        final o = FloorOptions.fromJson({
          'payment_methods': ['upi'],
          'start_presets': [60],
          'warn_minutes': 5,
        });
        expect(o.methodOr(PaymentMethod.cash), PaymentMethod.upi);
        expect(o.methodOr(PaymentMethod.upi), PaymentMethod.upi);
      },
    );
  });

  group('Customer birth year', () {
    test('empty is "not given"; outside 1900–this year is refused', () {
      expect(Customer.birthYearError('', 2026), isNull);
      expect(Customer.birthYearError('2009', 2026), isNull);
      expect(
        Customer.birthYearError('1899', 2026),
        'Enter a year from 1900 to 2026',
      );
      expect(
        Customer.birthYearError('2027', 2026),
        'Enter a year from 1900 to 2026',
      );
      expect(
        Customer.birthYearError('20x9', 2026),
        'Enter a year from 1900 to 2026',
      );
    });

    test('age is the year difference, or null when not given', () {
      final c = Customer(
        id: 'c',
        name: 'Diya',
        birthYear: 2009,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      expect(c.ageIn(2026), 17);
      expect(c.copyWith(birthYear: null).ageIn(2026), isNull);
    });
  });
}
