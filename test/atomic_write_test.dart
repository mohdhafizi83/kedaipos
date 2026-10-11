/// Data-safety tests: atomic file writes — a crash mid-write must never
/// corrupt the day's receipts, and a failed checkout burns no invoice number.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kedaipos/app/pos_service.dart';
import 'package:kedaipos/data/catalog_seed.dart';
import 'package:kedaipos/data/io_gateway.dart';
import 'package:kedaipos/data/store.dart';
import 'package:kedaipos/domain/cart.dart';
import 'package:kedaipos/domain/receipt.dart';

void main() {
  final day = DateTime(2026, 10, 11, 10, 0);
  final catalog = seedCatalog();
  Product byId(String id) => catalog.firstWhere((p) => p.id == id);

  group('IoFileGateway atomic write', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kedaipos_atomic'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('write then read roundtrips', () async {
      final gw = const IoFileGateway();
      final path = '${dir.path}/state.json';
      await gw.write(path, '{"a":1}');
      expect(await gw.read(path), '{"a":1}');
      await gw.write(path, '{"a":2}'); // overwrite via rename
      expect(await gw.read(path), '{"a":2}');
    });

    test('crash before rename leaves the OLD file intact and valid', () async {
      final gw = const IoFileGateway();
      final path = '${dir.path}/state.json';
      await gw.write(path, 'COMPLETE-OLD');

      // Simulate a crash in the window after the temp file is flushed but
      // before the atomic rename: the write throws, as if the power died.
      final crashy = IoFileGateway(
        debugBeforeRename: (_) =>
            throw const FileSystemException('simulated crash'),
      );
      await expectLater(
        crashy.write(path, 'HALF-NEW-CORRUPT-CONTENT'),
        throwsA(isA<FileSystemException>()),
      );

      // The target file is untouched: still the complete old content.
      expect(await gw.read(path), 'COMPLETE-OLD');
      // The littered temp file was cleaned up.
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('JsonFileStore: failed write keeps file valid and re-issues the '
        'number gap-free', () async {
      final path = '${dir.path}/pos-state.json';
      final good = const IoFileGateway();
      final store = JsonFileStore(path: path, gateway: good);
      await store.saveProducts(catalog);

      var service = await PosService.open(store);
      final first = await service.checkout(
        Cart()..add(byId('kopi-o')),
        at: day,
      );
      expect(first.number, 'INV-20261011-0001');

      // Swap in a gateway that crashes mid-write (disk full / power cut).
      final crashy = JsonFileStore(
        path: path,
        gateway: IoFileGateway(
          debugBeforeRename: (_) =>
              throw const FileSystemException('disk full'),
        ),
      );
      var crashService = await PosService.open(crashy);
      await expectLater(
        crashService.checkout(Cart()..add(byId('teh-tarik')), at: day),
        throwsA(isA<FileSystemException>()),
      );

      // The file on disk is still valid JSON with exactly ONE receipt —
      // the failed sale wrote nothing, and the number was rolled back.
      final recovered = JsonFileStore(path: path, gateway: good);
      final receipts = await recovered.loadReceipts();
      expect(receipts.length, 1);
      expect(receipts.single.number, 'INV-20261011-0001');

      // After "restart" the failed number is re-issued: no gap.
      crashService = await PosService.open(
        JsonFileStore(path: path, gateway: good),
      );
      final retry = await crashService.checkout(
        Cart()..add(byId('teh-tarik')),
        at: day,
      );
      expect(retry.number, 'INV-20261011-0002');
    });
  });

  group('ReceiptNumberGenerator.rollback', () {
    test(
      're-issues the rolled-back number (no gap burned by a failed write)',
      () {
        final gen = ReceiptNumberGenerator(now: () => day);
        final n1 = gen.next(); // counter = 1
        gen.rollback(n1); // write failed -> counter back to 0
        expect(gen.next(), 'INV-20261011-0001');
        gen.commit('INV-20261011-0001');
        final n2 = gen.next();
        gen.rollback(n2);
        expect(gen.next(), 'INV-20261011-0002');
      },
    );

    test('rollback never rewinds past a committed number', () {
      final gen = ReceiptNumberGenerator(now: () => day);
      final n = gen.next();
      gen.commit(n);
      gen.rollback(n); // must be a no-op
      expect(gen.next(), 'INV-20261011-0002');
    });
  });
}
