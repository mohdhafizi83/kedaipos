import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kedaipos/data/catalog_seed.dart';
import 'package:kedaipos/domain/cart.dart';
import 'package:kedaipos/domain/money.dart';
import 'package:kedaipos/domain/tax_engine.dart';

/// Property-style loop: for thousands of random carts, the receipt identity
/// `total == sum(lines) - discount + tax + rounding` must hold EXACTLY, and
/// the pro-rata discount allocation must never lose or duplicate a sen.
void main() {
  const engine = TaxEngine();
  final catalog = seedCatalog();
  final rng = Random(20261011); // seeded: deterministic, reproducible

  test('random carts: total identity holds exactly (2000 carts)', () {
    for (var i = 0; i < 2000; i++) {
      final cart = Cart();
      final lineCount = 1 + rng.nextInt(5);
      for (var l = 0; l < lineCount; l++) {
        cart.add(
          catalog[rng.nextInt(catalog.length)],
          quantity: 1 + rng.nextInt(9),
        );
      }
      switch (rng.nextInt(3)) {
        case 0: // no discount
          break;
        case 1:
          cart.applyDiscount(PercentDiscount(1 + rng.nextInt(20)));
        case 2:
          cart.applyDiscount(FlatDiscount(Money(rng.nextInt(1500))));
      }
      final tender = TenderType.values[rng.nextInt(3)];
      final t = engine.price(cart, tender: tender);

      var lineSum = Money.zero;
      for (final line in cart.lines) {
        lineSum += line.subtotal;
      }
      expect(t.subtotal, lineSum, reason: 'cart #$i subtotal');
      expect(
        t.subtotalWithTax,
        lineSum - t.discount + t.taxTotal,
        reason: 'cart #$i with-tax identity',
      );
      expect(
        t.total,
        lineSum - t.discount + t.taxTotal + t.rounding,
        reason: 'cart #$i total identity',
      );

      // Cash totals always sit on the 5-sen grid; card/eWallet never round.
      if (tender == TenderType.cash) {
        expect(t.total.sen % 5, 0, reason: 'cart #$i cash on 5-sen grid');
      } else {
        expect(t.rounding, Money.zero);
      }

      // Tax group bases sum exactly to the taxable base (no lost sen).
      final baseSum = t.taxGroups.fold(Money.zero, (s, g) => s + g.taxableBase);
      expect(baseSum, t.taxableBaseForTest, reason: 'cart #$i pro-rata');
    }
  });

  test(
    'random carts: SST never exceeds 8% of taxable base by more than 1 sen',
    () {
      for (var i = 0; i < 500; i++) {
        final cart = Cart();
        for (var l = 0; l < 1 + rng.nextInt(4); l++) {
          cart.add(
            catalog[rng.nextInt(catalog.length)],
            quantity: 1 + rng.nextInt(5),
          );
        }
        final t = engine.price(cart, tender: TenderType.card);
        final taxable = t.taxGroups
            .where((g) => g.percent == 8)
            .fold(Money.zero, (s, g) => s + g.taxableBase);
        // Per-group rounding can drift at most 1 sen per group; here 1 group.
        final ideal = taxable.sen * 8;
        final actual = t.taxTotal.sen * 100;
        final drift = (actual - ideal).abs();
        expect(
          drift,
          lessThanOrEqualTo(100),
          reason: 'cart #$i tax drift ${drift / 100} sen',
        );
      }
    },
  );
}

extension on Totals {
  Money get taxableBaseForTest => subtotal - discount;
}
