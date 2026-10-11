import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kedaipos/data/catalog_seed.dart';
import 'package:kedaipos/data/store.dart';
import 'package:kedaipos/domain/cart.dart';
import 'package:kedaipos/domain/money.dart';
import 'package:kedaipos/domain/receipt.dart';
import 'package:kedaipos/domain/tax_engine.dart';
import 'package:kedaipos/ui/day_close_screen.dart';
import 'package:kedaipos/ui/main.dart';

Widget _wrap(Widget w) => MaterialApp(home: w);

void main() {
  final day = DateTime(2026, 10, 11, 10, 0);

  Future<void> pumpHome(WidgetTester tester) async {
    final store = InMemoryStore(
      initial: PosState.empty().copyWith(products: seedCatalog()),
    );
    await tester.pumpWidget(_wrap(PosHomePage(initialRepository: store)));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a product adds it to cart and updates TOTAL', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('Cart kosong'), findsOneWidget);

    await tester.tap(find.text('Nasi Lemak'));
    await tester.pump();

    expect(find.text('Nasi Lemak'), findsWidgets); // tile + cart line
    // cart line shows the merged quantity
    expect(find.text('1 x RM6.50'), findsOneWidget);
    // subtotal 6.50 + SST 0.52 = 7.02 -> cash rounds to 7.00
    expect(find.text('RM7.00'), findsWidgets);
    expect(find.text('TOTAL'), findsOneWidget);
  });

  testWidgets('checkout navigates to receipt screen with receipt number', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Kopi O'));
    await tester.pump();
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();

    expect(
      find.text('INV-20261011-0001'.replaceFirst('20261011', _today())),
      findsOneWidget,
    );
    expect(find.textContaining('TOTAL'), findsWidgets);
    expect(find.textContaining('SST 8%'), findsWidgets);
  });

  testWidgets('day close screen shows SST collected', (tester) async {
    final r = Receipt(
      number: 'INV-20261011-0001',
      issuedAt: day,
      lines: [
        CartLine(
          product: const Product(
            id: 'x',
            name: 'X',
            unitPrice: Money(650),
            taxPercent: 8,
          ),
          quantity: 2,
        ),
      ],
      tender: TenderType.cash,
      totals: const Totals(
        subtotal: Money(1300),
        discount: Money.zero,
        taxGroups: [
          TaxGroup(percent: 8, taxableBase: Money(1300), tax: Money(104)),
        ],
        taxTotal: Money(104),
        subtotalWithTax: Money(1404),
        rounding: Money(1),
        total: Money(1405),
      ),
    );
    await tester.pumpWidget(_wrap(DayCloseScreen(receipts: [r], day: day)));
    await tester.pumpAndSettle();

    expect(find.text('SST 8%'), findsOneWidget);
    expect(find.text('RM1.04'), findsOneWidget);
    // RM14.05 appears as both the cash tender line and NET SALES (one receipt).
    expect(find.text('RM14.05'), findsAtLeastNWidgets(1));
  });

  testWidgets('discount button changes totals before checkout', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Nasi Lemak'));
    await tester.pump();
    // apply 10% discount
    await tester.tap(find.text('10%'));
    await tester.pump();
    // 6.50 - 0.65 = 5.85, SST 8% = 0.47 -> 6.32 -> cash 6.30
    expect(find.text('RM6.30'), findsOneWidget);
    expect(find.text('-RM0.65'), findsOneWidget);
  });
}

/// Today's YYYYMMDD for the receipt number the app stamps (uses DateTime.now).
String _today() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.day.toString().padLeft(2, '0')}';
}
