import 'package:flutter_test/flutter_test.dart';
import 'package:kedaipos/domain/cart.dart';
import 'package:kedaipos/domain/money.dart';
import 'package:kedaipos/domain/tax_engine.dart';

const nasiLemak = Product(
  id: 'nasi-lemak',
  name: 'Nasi Lemak',
  unitPrice: Money(650),
  taxPercent: 8,
);
const airMineral = Product(
  id: 'air-mineral',
  name: 'Mineral Water',
  unitPrice: Money(100),
  taxPercent: 0,
);
const indomie = Product(
  id: 'indomie',
  name: 'Indomie',
  unitPrice: Money(310),
  taxPercent: 0,
);

void main() {
  const engine = TaxEngine();

  group('Cart invariants', () {
    test('add merges same product, qty accumulates', () {
      final c = Cart()
        ..add(nasiLemak)
        ..add(nasiLemak, quantity: 2);
      expect(c.lineCount, 1);
      expect(c.totalQuantity, 3);
      expect(c.subtotal, Money(1950));
    });

    test('setQuantity updates and removes at zero', () {
      final c = Cart()
        ..add(nasiLemak)
        ..add(airMineral);
      c.setQuantity('nasi-lemak', 4);
      expect(c.subtotal, Money(650 * 4 + 100));
      c.setQuantity('nasi-lemak', 0);
      expect(c.lineCount, 1);
      expect(c.subtotal, Money(100));
    });

    test('removeLine removes and reports', () {
      final c = Cart()..add(nasiLemak);
      expect(c.removeLine('nasi-lemak'), isTrue);
      expect(c.removeLine('nasi-lemak'), isFalse);
      expect(c.isEmpty, isTrue);
    });

    test('add rejects non-positive quantity', () {
      expect(() => Cart().add(nasiLemak, quantity: 0), throwsArgumentError);
      expect(() => Cart().add(nasiLemak, quantity: -1), throwsArgumentError);
    });

    test('flat discount clamps to subtotal (never negative total)', () {
      final c = Cart()
        ..add(airMineral)
        ..applyDiscount(const FlatDiscount(Money(500)));
      expect(c.discountAmount, Money(100)); // clamped to subtotal
      expect(c.taxableBase, Money.zero);
    });

    test('percent discount is exact', () {
      final c = Cart()
        ..add(nasiLemak)
        ..applyDiscount(const PercentDiscount(10));
      // 6.50 * 10% = 0.65
      expect(c.discountAmount, Money(65));
      expect(c.taxableBase, Money(585));
    });

    test('clear removes lines and discount', () {
      final c = Cart()
        ..add(nasiLemak)
        ..applyDiscount(const PercentDiscount(10));
      c.clear();
      expect(c.isEmpty, isTrue);
      expect(c.discount, isNull);
    });
  });

  group('TaxEngine SST mix + discount-before-tax', () {
    test('mixed taxable + zero-rated produces two groups, tax only on 8%', () {
      final c = Cart()
        ..add(nasiLemak) // 6.50 taxable
        ..add(airMineral, quantity: 2); // 2.00 zero-rated
      final groups = engine.taxBreakdown(c);
      expect(groups.length, 2);
      final g8 = groups.firstWhere((g) => g.percent == 8);
      expect(g8.taxableBase, Money(650));
      expect(g8.tax, Money(52)); // 6.50 * 8% = 0.52
      final g0 = groups.firstWhere((g) => g.percent == 0);
      expect(g0.tax, Money.zero);
    });

    test('discount is applied BEFORE tax (tax on discounted base)', () {
      // One taxable line: 25.90, 10% off -> 23.31 base -> 8% = 1.8648 -> 1.86
      final c = Cart()
        ..add(nasiLemak, quantity: 3)
        ..add(
          const Product(
            id: 'milo-ais',
            name: 'Milo Ais',
            unitPrice: Money(320),
            taxPercent: 8,
          ),
          quantity: 2,
        );
      c.applyDiscount(const PercentDiscount(10));
      final totals = engine.price(c, tender: TenderType.card);
      expect(totals.subtotal, Money(2590));
      expect(totals.discount, Money(259));
      // If tax were computed BEFORE discount it would be 2590*8% = 207 sen.
      // Correct (discount-first): 2331 * 8% = 186.48 -> 186 sen.
      expect(totals.taxTotal, Money(186));
      expect(totals.total, Money(2590 - 259 + 186));
    });

    test('pro-rata discount across lines sums exactly (no lost sen)', () {
      // 3 lines, RM1 flat discount: bases must sum to subtotal - discount.
      final c = Cart()
        ..add(nasiLemak)
        ..add(airMineral)
        ..add(indomie)
        ..applyDiscount(const FlatDiscount(Money(100)));
      final groups = engine.taxBreakdown(c);
      final baseSum = groups.fold(Money.zero, (s, g) => s + g.taxableBase);
      expect(baseSum, c.taxableBase); // exact, no sen lost
    });

    test('empty cart prices to zero', () {
      final totals = engine.price(Cart());
      expect(totals.total, Money.zero);
      expect(totals.taxGroups, isEmpty);
    });
  });

  group('Cash rounding at tender', () {
    test('cash tender rounds total to nearest 5 sen with rounding line', () {
      // 16.00 + 1.28 SST = 17.28 -> 17.30 (+0.02)
      final c = Cart()
        ..add(nasiLemak, quantity: 2)
        ..add(
          const Product(
            id: 'teh-tarik',
            name: 'Teh Tarik',
            unitPrice: Money(300),
            taxPercent: 8,
          ),
        );
      final totals = engine.price(c, tender: TenderType.cash);
      expect(totals.subtotalWithTax, Money(1728));
      expect(totals.rounding, Money(2));
      expect(totals.total, Money(1730));
    });

    test('card tender never rounds', () {
      final c = Cart()
        ..add(nasiLemak, quantity: 2)
        ..add(
          const Product(
            id: 'teh-tarik',
            name: 'Teh Tarik',
            unitPrice: Money(300),
            taxPercent: 8,
          ),
        );
      final totals = engine.price(c, tender: TenderType.card);
      expect(totals.rounding, Money.zero);
      expect(totals.total, Money(1728));
    });

    test('eWallet tender never rounds', () {
      final c = Cart()..add(nasiLemak);
      final totals = engine.price(c, tender: TenderType.eWallet);
      expect(totals.rounding, Money.zero);
    });

    test('rounding can be negative (round down)', () {
      // 12.10 subtotal: mee 7.00 taxable + 5.10 zero-rated -> SST 0.56
      // total 12.66 -> 12.65 (-0.01)
      final c = Cart()
        ..add(
          const Product(
            id: 'mee',
            name: 'Mee',
            unitPrice: Money(700),
            taxPercent: 8,
          ),
        )
        ..add(airMineral, quantity: 2)
        ..add(indomie);
      final totals = engine.price(c);
      expect(totals.subtotalWithTax, Money(1266));
      expect(totals.rounding, Money(-1));
      expect(totals.total, Money(1265));
    });
  });
}
