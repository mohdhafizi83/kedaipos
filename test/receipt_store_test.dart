import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kedaipos/app/pos_service.dart';
import 'package:kedaipos/data/catalog_seed.dart';
import 'package:kedaipos/data/store.dart';
import 'package:kedaipos/domain/cart.dart';
import 'package:kedaipos/domain/money.dart';
import 'package:kedaipos/domain/receipt.dart';
import 'package:kedaipos/domain/tax_engine.dart';

/// Fake gateway backed by a Map — proves JsonFileStore roundtrips through
/// real JSON text without touching dart:io.
class FakeGateway implements FileGateway {
  final Map<String, String> files = {};

  @override
  Future<String?> read(String path) async => files[path];

  @override
  Future<void> write(String path, String content) async {
    files[path] = content;
  }
}

void main() {
  final day = DateTime(2026, 10, 11, 10, 0);
  final catalog = seedCatalog();
  Product byId(String id) => catalog.firstWhere((p) => p.id == id);

  group('ReceiptNumberGenerator', () {
    test('formats INV-YYYYMMDD-0001 with zero padding', () {
      final gen = ReceiptNumberGenerator(now: () => day);
      expect(gen.next(), 'INV-20261011-0001');
      expect(gen.next(), 'INV-20261011-0002');
    });

    test('sequence is monotonic and gap-free across midnight', () {
      var current = DateTime(2026, 10, 11, 23, 59);
      final gen = ReceiptNumberGenerator(now: () => current);
      expect(gen.next(), 'INV-20261011-0001');
      current = current.add(const Duration(minutes: 2)); // next day
      expect(gen.next(), 'INV-20261012-0001'); // fresh per-day counter
      expect(gen.next(), 'INV-20261012-0002');
    });

    test('peekNext does not consume', () {
      final gen = ReceiptNumberGenerator(now: () => day);
      expect(gen.peekNext(), 'INV-20261011-0001');
      expect(gen.peekNext(), 'INV-20261011-0001');
      expect(gen.next(), 'INV-20261011-0001');
      expect(gen.peekNext(), 'INV-20261011-0002');
    });

    test('commit twice throws (replay safety)', () {
      final gen = ReceiptNumberGenerator(now: () => day);
      final n = gen.next();
      gen.commit(n);
      expect(() => gen.commit(n), throwsA(isA<DuplicateReceiptException>()));
    });

    test('counters survive JSON roundtrip (restart)', () {
      final gen = ReceiptNumberGenerator(now: () => day);
      gen.next();
      gen.next();
      gen.commit('INV-20261011-0002');
      final json = jsonEncode(gen.toJson());

      final restored = ReceiptNumberGenerator.restore(
        json: jsonDecode(json) as Map<String, dynamic>,
        now: () => day,
      );
      expect(restored.next(), 'INV-20261011-0003');
      // previously committed number is still guarded after restore
      expect(
        () => restored.commit('INV-20261011-0002'),
        throwsA(isA<DuplicateReceiptException>()),
      );
    });

    test('counters can be recovered from receipts alone', () {
      final receipts = [
        Receipt(
          number: 'INV-20261011-0003',
          issuedAt: day,
          lines: const [],
          totals: const Totals(
            subtotal: Money.zero,
            discount: Money.zero,
            taxGroups: [],
            taxTotal: Money.zero,
            subtotalWithTax: Money.zero,
            rounding: Money.zero,
            total: Money.zero,
          ),
          tender: TenderType.cash,
        ),
        Receipt(
          number: 'INV-20261011-0007',
          issuedAt: day,
          lines: const [],
          totals: const Totals(
            subtotal: Money.zero,
            discount: Money.zero,
            taxGroups: [],
            taxTotal: Money.zero,
            subtotalWithTax: Money.zero,
            rounding: Money.zero,
            total: Money.zero,
          ),
          tender: TenderType.cash,
        ),
      ];
      final counters = ReceiptNumberGenerator.countersFromReceipts(receipts);
      expect(counters['20261011'], 7);
    });
  });

  group('JsonFileStore roundtrip', () {
    test('products and receipts survive save/load through JSON text', () async {
      final gw = FakeGateway();
      final store = JsonFileStore(path: 'pos.json', gateway: gw);
      await store.saveProducts(catalog);

      final cart = Cart()..add(byId('nasi-lemak'));
      final service = await PosService.open(store);
      final receipt = await service.checkout(cart, at: day);

      // Fresh store instance reading the same gateway = simulated restart.
      final reopened = JsonFileStore(path: 'pos.json', gateway: gw);
      final products = await reopened.loadProducts();
      expect(products.length, catalog.length);
      expect(products.first.unitPrice, catalog.first.unitPrice);

      final receipts = await reopened.loadReceipts();
      expect(receipts.single.number, receipt.number);
      expect(receipts.single.totals.total, receipt.totals.total);
      expect(receipts.single.lines.single.product.name, 'Nasi Lemak');

      // The file really is JSON text on the "disk".
      expect(() => jsonDecode(gw.files['pos.json']!), returnsNormally);
    });

    test('restart continues receipt sequence gap-free', () async {
      final gw = FakeGateway();
      final store = JsonFileStore(path: 'pos.json', gateway: gw);
      await store.saveProducts(catalog);
      var service = await PosService.open(store);
      await service.checkout(Cart()..add(byId('kopi-o')), at: day);
      await service.checkout(Cart()..add(byId('kopi-o')), at: day);

      // "Restart": brand-new service over the same file.
      service = await PosService.open(
        JsonFileStore(path: 'pos.json', gateway: gw),
      );
      final third = await service.checkout(
        Cart()..add(byId('kopi-o')),
        at: day,
      );
      expect(third.number, 'INV-20261011-0003');
    });
  });

  group('PosService checkout', () {
    test('checkout rejects empty cart', () async {
      final service = await PosService.open(InMemoryStore());
      expect(() => service.checkout(Cart()), throwsStateError);
    });

    test(
      'receipt total == lines - discount + tax + rounding EXACTLY',
      () async {
        final store = InMemoryStore(
          initial: PosState.empty().copyWith(products: catalog),
        ); // ignore: prefer_const_constructors
        final service = await PosService.open(store);

        final cart = Cart()
          ..add(byId('nasi-lemak'), quantity: 2)
          ..add(byId('air-mineral'))
          ..applyDiscount(const PercentDiscount(10));
        final receipt = await service.checkout(cart, at: day);
        final t = receipt.totals;
        var lineSum = Money.zero;
        for (final l in receipt.lines) {
          lineSum += l.subtotal;
        }
        expect(t.total, lineSum - t.discount + t.taxTotal + t.rounding);
      },
    );
  });

  group('DayReport', () {
    test('aggregates only the target day', () {
      final r1 = _stubReceipt(
        'INV-20261011-0001',
        Money(1000),
        Money(80),
        Money(5),
        TenderType.cash,
      );
      final r2 = _stubReceipt(
        'INV-20261011-0002',
        Money(2000),
        Money(160),
        Money(-5),
        TenderType.card,
      );
      final r3 = _stubReceipt(
        'INV-20261012-0001',
        Money(500),
        Money(40),
        Money(0),
        TenderType.cash,
      );
      final report = DayReport.forDay([r1, r2, r3], DateTime(2026, 10, 11));
      expect(report.receiptCount, 2);
      expect(report.grossSales, Money(3000));
      expect(report.sstCollected, Money(240));
      expect(report.totalRounding, Money(0));
      expect(report.netSales, Money(1085 + 2155));
      expect(report.byTender[TenderType.cash], Money(1085));
      expect(report.byTender[TenderType.card], Money(2155));
    });
  });
}

Receipt _stubReceipt(
  String number,
  Money subtotal,
  Money tax,
  Money rounding,
  TenderType tender,
) {
  return Receipt(
    number: number,
    issuedAt: DateTime(2026, 10, 11),
    lines: const [],
    tender: tender,
    totals: Totals(
      subtotal: subtotal,
      discount: Money.zero,
      taxGroups: [TaxGroup(percent: 8, taxableBase: subtotal, tax: tax)],
      taxTotal: tax,
      subtotalWithTax: subtotal + tax,
      rounding: rounding,
      total: subtotal + tax + rounding,
    ),
  );
}
