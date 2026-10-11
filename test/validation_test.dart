/// Domain-boundary input guards: the UI's +/- buttons and price entry are
/// convenience, not validation — the domain rejects NaN/negative/oversized
/// values even in release builds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kedaipos/data/catalog_seed.dart';
import 'package:kedaipos/domain/cart.dart';
import 'package:kedaipos/domain/money.dart';

void main() {
  final catalog = seedCatalog();
  Product byId(String id) => catalog.firstWhere((p) => p.id == id);

  group('Money.parse rejects junk a text field can produce', () {
    test('NaN/Infinity/exponent/hex junk', () {
      for (final junk in [
        'NaN',
        'nan',
        'Infinity',
        '-Infinity',
        '1e999',
        '0x10',
      ]) {
        expect(
          () => Money.parse(junk),
          throwsA(isA<MoneyParseException>()),
          reason: '"$junk" must not parse as money',
        );
      }
    });

    test('oversized amounts (overflow guard)', () {
      expect(
        () => Money.parse('99999999999999999.99'),
        throwsA(isA<MoneyParseException>()),
      );
      // maxSen is the documented ceiling; just above it throws.
      expect(
        () => Money.parse('${(Money.maxSen ~/ 100) + 1}'),
        throwsA(isA<MoneyParseException>()),
      );
    });
  });

  group('Cart quantity guards', () {
    test('Cart.add rejects zero, negative, and oversized quantities', () {
      final cart = Cart();
      final p = byId('kopi-o');
      expect(() => cart.add(p, quantity: 0), throwsArgumentError);
      expect(() => cart.add(p, quantity: -5), throwsArgumentError);
      expect(
        () => cart.add(p, quantity: CartLine.maxQuantity + 1),
        throwsArgumentError,
      );
    });

    test('Cart.add rejects merged quantity beyond the cap', () {
      final cart = Cart();
      final p = byId('kopi-o');
      cart.add(p, quantity: CartLine.maxQuantity - 10);
      expect(() => cart.add(p, quantity: 11), throwsArgumentError);
      // the rejected add left the line untouched
      expect(cart.lines.single.quantity, CartLine.maxQuantity - 10);
    });

    test('CartLine rejects non-positive quantity even in release mode', () {
      // assert() would vanish in release; this must be a real throw.
      expect(
        () => CartLine(product: byId('kopi-o'), quantity: 0),
        throwsArgumentError,
      );
      expect(
        () => CartLine(product: byId('kopi-o'), quantity: -3),
        throwsArgumentError,
      );
    });

    test('setQuantity rejects oversized values', () {
      final cart = Cart()..add(byId('kopi-o'));
      expect(
        () => cart.setQuantity('kopi-o', CartLine.maxQuantity + 1),
        throwsArgumentError,
      );
    });
  });

  group('Discount guards', () {
    test('PercentDiscount rejects out-of-range percentages', () {
      expect(
        () => const PercentDiscount(-1).applyTo(Money(1000)),
        throwsArgumentError,
      );
      expect(
        () => const PercentDiscount(101).applyTo(Money(1000)),
        throwsArgumentError,
      );
      expect(const PercentDiscount(100).applyTo(Money(1000)), Money(1000));
    });

    test('FlatDiscount never goes negative (a negative voucher cannot inflate '
        'the bill)', () {
      expect(const FlatDiscount(Money(-500)).applyTo(Money(1000)), Money.zero);
      // oversized flat discount still clamps to the base, never below zero
      expect(
        const FlatDiscount(Money(99999)).applyTo(Money(1000)),
        Money(1000),
      );
    });
  });
}
