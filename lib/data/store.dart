/// Repository interfaces + stores.
///
/// `JsonFileStore` is pure Dart with an injectable [FileGateway] — it never
/// imports `dart:io` directly, so the same code compiles for web (where the
/// UI uses [InMemoryStore]) and for the CLI demo (which injects a real
/// file gateway). This keeps the persistence layer honest and testable.
library;

import 'dart:convert';

import '../domain/cart.dart';
import '../domain/money.dart';
import '../domain/receipt.dart';

/// Persistence port for the POS.
abstract class PosRepository {
  Future<List<Product>> loadProducts();
  Future<void> saveProducts(List<Product> products);

  Future<List<Receipt>> loadReceipts();

  /// Persist a receipt together with the receipt-number state, as one
  /// atomic state write. Called before the number is committed, so a failed
  /// write never burns a sequence number.
  Future<void> saveState(PosState state);

  Future<PosState> loadState();
}

/// Everything that lives in the JSON file: products, receipts, counters.
class PosState {
  final List<Product> products;
  final List<Receipt> receipts;
  final Map<String, int> counters;
  final Set<String> issuedNumbers;

  const PosState({
    required this.products,
    required this.receipts,
    required this.counters,
    required this.issuedNumbers,
  });

  PosState.empty()
    : products = const [],
      receipts = const [],
      counters = const {},
      issuedNumbers = const {};

  PosState copyWith({
    List<Product>? products,
    List<Receipt>? receipts,
    Map<String, int>? counters,
    Set<String>? issuedNumbers,
  }) => PosState(
    products: products ?? this.products,
    receipts: receipts ?? this.receipts,
    counters: counters ?? this.counters,
    issuedNumbers: issuedNumbers ?? this.issuedNumbers,
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'products': [
      for (final p in products)
        {
          'id': p.id,
          'name': p.name,
          'unitPriceSen': p.unitPrice.sen,
          'taxPercent': p.taxPercent,
        },
    ],
    'receipts': [for (final r in receipts) r.toJson()],
    'counters': counters,
    'issued': issuedNumbers.toList()..sort(),
  };

  factory PosState.fromJson(Map<String, dynamic> json) => PosState(
    products: [
      for (final p
          in (json['products'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
        Product(
          id: p['id'] as String,
          name: p['name'] as String,
          unitPrice: Money(p['unitPriceSen'] as int),
          taxPercent: p['taxPercent'] as int,
        ),
    ],
    receipts: [
      for (final r
          in (json['receipts'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
        Receipt.fromJson(r),
    ],
    counters: {
      for (final e
          in (json['counters'] as Map<String, dynamic>? ?? const {}).entries)
        e.key: e.value as int,
    },
    issuedNumbers: (json['issued'] as List? ?? const []).cast<String>().toSet(),
  );
}

/// File IO port: inject real (dart:io) or fake (tests/web) implementations.
abstract class FileGateway {
  Future<String?> read(String path);
  Future<void> write(String path, String content);
}

const JsonEncoder jsonEncoder = JsonEncoder.withIndent('  ');

/// Pure-Dart JSON-file store. All IO goes through [FileGateway].
class JsonFileStore implements PosRepository {
  final String path;
  final FileGateway gateway;

  JsonFileStore({required this.path, required this.gateway});

  PosState? _cache;

  Future<PosState> _read() async {
    if (_cache != null) return _cache!;
    final raw = await gateway.read(path);
    if (raw == null || raw.trim().isEmpty) {
      _cache = PosState.empty();
    } else {
      _cache = PosState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    return _cache!;
  }

  Future<void> _write(PosState state) async {
    _cache = state;
    // Single write of the whole state = atomic enough for a single terminal
    // (see README limitations). A production store would use a temp-file +
    // rename dance or a real database transaction.
    await gateway.write(path, jsonEncoder.convert(state.toJson()));
  }

  @override
  Future<List<Product>> loadProducts() async => (await _read()).products;

  @override
  Future<void> saveProducts(List<Product> products) async {
    final s = await _read();
    await _write(s.copyWith(products: products));
  }

  @override
  Future<List<Receipt>> loadReceipts() async => (await _read()).receipts;

  @override
  Future<PosState> loadState() => _read();

  @override
  Future<void> saveState(PosState state) => _write(state);
}

/// In-memory store for the web UI and tests.
class InMemoryStore implements PosRepository {
  PosState _state;

  InMemoryStore({PosState? initial}) : _state = initial ?? PosState.empty();

  @override
  Future<List<Product>> loadProducts() async => _state.products;

  @override
  Future<void> saveProducts(List<Product> products) async {
    _state = _state.copyWith(products: products);
  }

  @override
  Future<List<Receipt>> loadReceipts() async => _state.receipts;

  @override
  Future<PosState> loadState() async => _state;

  @override
  Future<void> saveState(PosState state) async => _state = state;
}
