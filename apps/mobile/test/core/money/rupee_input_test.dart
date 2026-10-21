/// Rupee text → integer paise, exactly. Every amount typed into a payment,
/// end-of-session or rate field goes through this parser, so it must never
/// lose (or invent) a paisa the way `double * 100` does.
library;

import 'package:arena_ops/core/money/rupee_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRupeesToPaise accepts plain rupee amounts', () {
    const cases = {
      '19.99': 1999,
      '0.10': 10,
      '0.1': 10,
      '250': 25000,
      '250.5': 25050,
      '250.50': 25050,
      '0': 0,
      '0.00': 0,
      '.5': 50,
      '250.': 25000,
      '  300  ': 30000,
      '000250': 25000,
      '1,000': 100000,
      '1,000.5': 100050,
      '12,345.67': 1234567,
      '1,000,000': 100000000,
      '1,00,000': 10000000, // Indian grouping: one lakh
      '10,00,000.25': 100000025,
      '1,00,00,000': 1000000000, // one crore — the ceiling
    };
    for (final e in cases.entries) {
      test('"${e.key}" → ${e.value} paise', () {
        expect(parseRupeesToPaise(e.key), e.value);
      });
    }
  });

  group('parseRupeesToPaise refuses what is not an amount', () {
    const rejected = [
      '', // empty
      '   ', // blank
      '.', // no digits
      '-5', // negative
      '-0.50',
      '+5', // signs are not amounts
      '0.005', // three decimals
      '1.005',
      '1.000',
      '1.2.3', // two points
      'abc', // non-numeric
      '12a',
      '₹100', // the ₹ is the field's prefix, not part of the number
      '1e3', // no scientific notation
      '1 000', // inner space
      '1,5', // a decimal comma must never read as fifteen
      '1,0000',
      ',500',
      '500,',
      '1,,000',
      '12,34,5678',
      '1,000.123',
      '1,00,00,000.01', // one paisa over the ceiling
      '100000001', // ₹10,00,00,001
      '99999999999999999999', // 20 digits: overflow territory
      '123456789012345678901234567890', // very long input
      'NaN',
      'Infinity',
    ];
    for (final text in rejected) {
      test('"$text" is refused', () {
        expect(parseRupeesToPaise(text), isNull);
      });
    }
  });

  group('regressions double arithmetic gets wrong', () {
    test('1.005 is refused, where double math quietly makes it ₹1.00', () {
      // The old code path: 1.005 * 100 is 100.49999999999999.
      expect((double.parse('1.005') * 100).round(), 100);
      expect(parseRupeesToPaise('1.005'), isNull);
    });

    test('4.35 is exactly 435, though 4.35 * 100 is 434.99999999999994', () {
      expect(double.parse('4.35') * 100, isNot(435));
      expect((double.parse('4.35') * 100).truncate(), 434);
      expect(parseRupeesToPaise('4.35'), 435);
    });

    test('19.99 is exactly 1999, though 19.99 * 100 is 1998.9999999999998', () {
      expect((double.parse('19.99') * 100).truncate(), 1998);
      expect(parseRupeesToPaise('19.99'), 1999);
    });

    test('1159.99 is exactly 115999', () {
      expect(parseRupeesToPaise('1159.99'), 115999);
    });

    test('every paisa amount up to ₹100 round-trips exactly', () {
      for (var p = 0; p <= 10000; p++) {
        expect(
          parseRupeesToPaise(paiseToRupeeInput(p)),
          p,
          reason: paiseToRupeeInput(p),
        );
      }
    });
  });

  group('paiseToRupeeInput', () {
    test('formats prefill text with two decimals, no grouping', () {
      expect(paiseToRupeeInput(1999), '19.99');
      expect(paiseToRupeeInput(50000), '500.00');
      expect(paiseToRupeeInput(5), '0.05');
      expect(paiseToRupeeInput(0), '0.00');
      expect(paiseToRupeeInput(123456789), '1234567.89');
    });
  });
}
