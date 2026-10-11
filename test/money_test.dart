import 'package:flutter_test/flutter_test.dart';
import 'package:kedaipos/domain/money.dart';

void main() {
  group('Money parse', () {
    test('parses plain decimals exactly', () {
      expect(Money.parse('6.50').sen, 650);
      expect(Money.parse('3.2').sen, 320);
      expect(Money.parse('1').sen, 100);
      expect(Money.parse('0.05').sen, 5);
      expect(Money.parse('0').sen, 0);
    });

    test('parses RM prefix and whitespace', () {
      expect(Money.parse('RM6.50').sen, 650);
      expect(Money.parse(' RM12.34 ').sen, 1234);
      expect(Money.parse('rm1.00').sen, 100);
    });

    test('parses thousands separators', () {
      expect(Money.parse('1,234.56').sen, 123456);
      expect(Money.parse('1,000').sen, 100000);
      expect(Money.parse('12,345,678.90').sen, 1234567890);
    });

    test('rejects malformed strings', () {
      expect(() => Money.parse('1,23'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('1.005'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('1.2.3'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('abc'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse(''), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('RM'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('12,'), throwsA(isA<MoneyParseException>()));
      expect(() => Money.parse('-'), throwsA(isA<MoneyParseException>()));
    });

    test('parses negatives', () {
      expect(Money.parse('-3.20').sen, -320);
      expect(Money.parse('-0.01').sen, -1);
      expect(Money.parse('+2.50').sen, 250);
    });

    test('tryParse returns null instead of throwing', () {
      expect(Money.tryParse('6.50')?.sen, 650);
      expect(Money.tryParse('nonsense'), isNull);
    });

    test('classic float trap: 0.1 + 0.2 == 0.3 exactly', () {
      expect(Money.parse('0.10') + Money.parse('0.20'), Money.parse('0.30'));
    });
  });

  group('Money arithmetic', () {
    test('add/sub/negate', () {
      expect(Money(650) + Money(320), Money(970));
      expect(Money(650) - Money(650), Money.zero);
      expect(-Money(100), Money(-100));
    });

    test('multiply by int quantity', () {
      expect(Money(650) * 3, Money(1950));
      expect(Money(250) * 0, Money.zero);
    });

    test('multiplyRatio 8% rounds half-up exactly', () {
      // 13.00 * 8% = 1.04 exactly
      expect(Money(1300).multiplyRatio(8, 100), Money(104));
      // 0.31 * 8% = 2.48 sen -> 2 sen
      expect(Money(31).multiplyRatio(8, 100), Money(2));
      // 0.32 * 8% = 2.56 sen -> 3 sen
      expect(Money(32).multiplyRatio(8, 100), Money(3));
      // exact half: 0.3125*8... use 12.5 sen * 8/100 = 1.0 sen? pick:
      // 6 sen * 8/100 = 0.48 -> 0; 7 sen * 8/100 = 0.56 -> 1
      expect(Money(6).multiplyRatio(8, 100), Money(0));
      expect(Money(7).multiplyRatio(8, 100), Money(1));
      // exact half case: x * 8/100 with remainder exactly half:
      // 11 sen * 8 = 88, /100 -> q0 r88 -> 1. For half: r*2==den: r=50:
      // n*8 % 100 == 50 impossible for 8/100; test with 5/100: 15*5=75 -> r75?
      expect(Money(15).multiplyRatio(5, 100), Money(1)); // 0.75 -> 1
      expect(Money(5).multiplyRatio(5, 100), Money(0)); // 0.25 -> 0
      expect(Money(25).multiplyRatio(1, 10), Money(3)); // 2.5 -> 3 (half up)
    });

    test('multiplyRatio floor mode truncates', () {
      expect(Money(32).multiplyRatio(8, 100, halfUp: false), Money(2));
    });

    test('multiplyRatio rejects zero denominator', () {
      expect(() => Money(100).multiplyRatio(8, 0), throwsArgumentError);
    });
  });

  group('Money roundToNearest (5 sen)', () {
    test('rounds every sen digit 0-9 to nearest 0.05, halves up', () {
      // base RM10.00 + x sen -> expected after 5-sen rounding
      const table = {
        0: 0, 1: 0, 2: 0, 3: 5, 4: 5, //
        5: 5, 6: 5, 7: 5, 8: 10, 9: 10,
      };
      table.forEach((x, expected) {
        expect(
          Money(1000 + x).roundToNearest(5).sen,
          1000 + expected,
          reason:
              'RM10.0$x should round to RM10.${expected.toString().padLeft(2, '0')}',
        );
      });
    });

    test('negative amounts round half away from zero', () {
      expect(Money(-12).roundToNearest(5), Money(-10));
      expect(Money(-13).roundToNearest(5), Money(-15));
      expect(Money(-2).roundToNearest(5), Money(0));
    });

    test('rejects non-positive step', () {
      expect(() => Money(10).roundToNearest(0), throwsArgumentError);
    });
  });

  group('Money format', () {
    test('toString always two decimals with RM prefix', () {
      expect(Money(650).toString(), 'RM6.50');
      expect(Money(5).toString(), 'RM0.05');
      expect(Money(100).toString(), 'RM1.00');
      expect(Money(-320).toString(), '-RM3.20');
      expect(Money.zero.toString(), 'RM0.00');
    });

    test('toStringWithSeparator groups thousands', () {
      expect(Money(123456).toStringWithSeparator(), 'RM1,234.56');
      expect(Money(1234567890).toStringWithSeparator(), 'RM12,345,678.90');
      expect(Money(99999).toStringWithSeparator(), 'RM999.99');
      expect(Money(-123456).toStringWithSeparator(), '-RM1,234.56');
    });

    test('roundtrip parse(toString) is identity', () {
      for (final sen in [0, 1, 5, 99, 100, 650, 123456, -320]) {
        expect(Money.parse(Money(sen).toString()), Money(sen));
      }
    });
  });
}
