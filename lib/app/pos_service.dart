/// Application service: the single place checkout happens, shared by the
/// Flutter UI and the CLI demo so both exercise identical logic.
library;

import '../data/store.dart';
import '../domain/cart.dart';
import '../domain/receipt.dart';
import '../domain/tax_engine.dart';

class PosService {
  final PosRepository repo;
  final TaxEngine taxEngine;
  late final ReceiptNumberGenerator numbering;

  PosService._(this.repo, this.taxEngine, ReceiptNumberGenerator gen)
    : numbering = gen;

  /// Load state from the repository and rebuild the numbering generator
  /// from persisted counters (with recovery from receipts if counters are
  /// missing).
  static Future<PosService> open(
    PosRepository repo, {
    TaxEngine taxEngine = const TaxEngine(),
  }) async {
    final state = await repo.loadState();
    final counters = state.counters.isNotEmpty
        ? state.counters
        : ReceiptNumberGenerator.countersFromReceipts(state.receipts);
    final gen = ReceiptNumberGenerator(
      counters: counters,
      issuedNumbers: state.issuedNumbers,
    );
    return PosService._(repo, taxEngine, gen);
  }

  /// Price a cart for a tender type (no side effects).
  Totals price(Cart cart, {TenderType tender = TenderType.cash}) =>
      taxEngine.price(cart, tender: tender);

  /// Finalise a sale: issue number, persist receipt + counter atomically,
  /// then commit the number. Returns the immutable receipt.
  Future<Receipt> checkout(
    Cart cart, {
    TenderType tender = TenderType.cash,
    DateTime? at,
  }) async {
    if (cart.isEmpty) {
      throw StateError('cannot checkout an empty cart');
    }
    final totals = price(cart, tender: tender);
    final number = numbering.next(at);
    final receipt = Receipt(
      number: number,
      issuedAt: at ?? DateTime.now(),
      lines: cart.lines,
      totals: totals,
      tender: tender,
    );

    // Persist receipt + counter state BEFORE committing the number: if the
    // write throws, the number is rolled back (not marked issued) and will
    // be re-issued — the failed attempt burns no number, so the persisted
    // sequence stays gap-free.
    final state = await repo.loadState();
    try {
      await repo.saveState(
        state.copyWith(
          receipts: [...state.receipts, receipt],
          counters: numbering.counters,
          issuedNumbers: {...numbering.issuedNumbers, number},
        ),
      );
    } catch (_) {
      numbering.rollback(number);
      rethrow;
    }
    numbering.commit(number);
    return receipt;
  }

  Future<List<Product>> products() => repo.loadProducts();
  Future<List<Receipt>> receipts() => repo.loadReceipts();
}
