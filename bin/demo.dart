// Zero-credential deterministic demo: seeds a catalog into a temp JSON
// store, runs a 6-order trading day through the exact same service the
// Flutter app uses, prints every receipt, then the Z-report.
//
//   dart run bin/demo.dart
//
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:kedaipos/app/pos_service.dart';
import 'package:kedaipos/data/catalog_seed.dart';
import 'package:kedaipos/data/io_gateway.dart';
import 'package:kedaipos/data/store.dart';
import 'package:kedaipos/domain/cart.dart';
import 'package:kedaipos/domain/money.dart';
import 'package:kedaipos/domain/receipt.dart';
import 'package:kedaipos/domain/tax_engine.dart';

Future<void> main(List<String> args) async {
  final dir = Directory.systemTemp.createTempSync('kedaipos_demo');
  final store = JsonFileStore(
    path: '${dir.path}/pos-state.json',
    gateway: IoFileGateway(),
  );

  // Seed catalog on first run.
  final existing = await store.loadProducts();
  final catalog = existing.isEmpty ? seedCatalog() : existing;
  if (existing.isEmpty) {
    await store.saveProducts(catalog);
  }

  final service = await PosService.open(store);
  Product byId(String id) => catalog.firstWhere((p) => p.id == id);

  // A fixed trading day so output is deterministic.
  final day = DateTime(2026, 10, 11, 9, 30);
  DateTime at(int minutes) => day.add(Duration(minutes: minutes));

  // ---- Six orders through the real checkout path -------------------------
  final orders = <void Function(Cart c)>[
    // 1. Plain taxable order: 2x nasi lemak + teh tarik.
    (c) {
      c.add(byId('nasi-lemak'), quantity: 2);
      c.add(byId('teh-tarik'));
    },
    // 2. Mixed taxable + zero-rated essentials.
    (c) {
      c.add(byId('mee-goreng'));
      c.add(byId('air-mineral'), quantity: 2);
      c.add(byId('indomie'));
    },
    // 3. 10% staff discount on a taxable order (discount BEFORE tax).
    (c) {
      c.add(byId('nasi-lemak'), quantity: 3);
      c.add(byId('milo-ais'), quantity: 2);
      c.applyDiscount(const PercentDiscount(10));
    },
    // 4. Cash sale landing on x.x4 -> rounds UP to nearest 5 sen (+0.01).
    (c) {
      c.add(byId('nasi-lemak'), quantity: 2); // 13.00 taxable
      c.add(byId('air-mineral')); // 1.00 zero-rated
      // SST 8% on 13.00 = 1.04 -> 15.04 -> cash total 15.05
    },
    // 5. Card sale: never rounded, keeps exact sen.
    (c) {
      c.add(byId('nasi-lemak'));
      c.add(byId('milo-kotak'), quantity: 3);
      c.add(byId('telur-seping'));
    },
    // 6. Flat RM1 voucher on a mixed basket, cash tender.
    (c) {
      c.add(byId('mee-goreng'), quantity: 2);
      c.add(byId('kopi-instant'));
      c.add(byId('keropok'));
      c.applyDiscount(const FlatDiscount(Money(100)));
    },
  ];

  final receipts = <Receipt>[];
  for (var i = 0; i < orders.length; i++) {
    final cart = Cart();
    orders[i](cart);
    final tender = i == 4 ? TenderType.card : TenderType.cash;
    final receipt = await service.checkout(cart, tender: tender, at: at(i * 7));
    receipts.add(receipt);
    print('=' * 38);
    print(renderReceiptText(receipt));
  }

  // ---- Z-report -----------------------------------------------------------
  print('=' * 38);
  final report = DayReport.forDay(receipts, day);
  print(report.toText());

  // ---- Restart simulation: reopen store, prove sequencing survives --------
  final reopened = await PosService.open(
    JsonFileStore(path: '${dir.path}/pos-state.json', gateway: IoFileGateway()),
  );
  print('-' * 38);
  print(
    'After restart, next receipt number would be: '
    '${reopened.numbering.peekNext(day)}',
  );
  print(
    '(gap-free: counter restored from ${dir.path.split('/').last}/pos-state.json)',
  );

  dir.deleteSync(recursive: true);
}
