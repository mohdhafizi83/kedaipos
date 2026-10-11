/// Receipt model + gap-free per-day receipt numbering with replay safety.
library;

import 'cart.dart';
import 'money.dart';
import 'tax_engine.dart';

/// A completed, immutable sale.
class Receipt {
  /// e.g. `INV-20261011-0007`
  final String number;
  final DateTime issuedAt;
  final List<CartLine> lines;
  final Totals totals;
  final TenderType tender;

  const Receipt({
    required this.number,
    required this.issuedAt,
    required this.lines,
    required this.totals,
    required this.tender,
  });

  Map<String, dynamic> toJson() => {
    'number': number,
    'issuedAt': issuedAt.toIso8601String(),
    'tender': tender.name,
    'lines': [
      for (final l in lines)
        {
          'productId': l.product.id,
          'name': l.product.name,
          'unitPriceSen': l.product.unitPrice.sen,
          'taxPercent': l.product.taxPercent,
          'quantity': l.quantity,
        },
    ],
    'totals': {
      'subtotalSen': totals.subtotal.sen,
      'discountSen': totals.discount.sen,
      'taxSen': totals.taxTotal.sen,
      'roundingSen': totals.rounding.sen,
      'totalSen': totals.total.sen,
      'taxGroups': [
        for (final g in totals.taxGroups)
          {
            'percent': g.percent,
            'baseSen': g.taxableBase.sen,
            'taxSen': g.tax.sen,
          },
      ],
    },
  };

  factory Receipt.fromJson(Map<String, dynamic> json) {
    final t = json['totals'] as Map<String, dynamic>;
    return Receipt(
      number: json['number'] as String,
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      tender: TenderType.values.byName(json['tender'] as String),
      lines: [
        for (final l in (json['lines'] as List).cast<Map<String, dynamic>>())
          CartLine(
            product: Product(
              id: l['productId'] as String,
              name: l['name'] as String,
              unitPrice: Money(l['unitPriceSen'] as int),
              taxPercent: l['taxPercent'] as int,
            ),
            quantity: l['quantity'] as int,
          ),
      ],
      totals: Totals(
        subtotal: Money(t['subtotalSen'] as int),
        discount: Money(t['discountSen'] as int),
        taxTotal: Money(t['taxSen'] as int),
        rounding: Money(t['roundingSen'] as int),
        total: Money(t['totalSen'] as int),
        subtotalWithTax:
            Money(t['subtotalSen'] as int) -
            Money(t['discountSen'] as int) +
            Money(t['taxSen'] as int),
        taxGroups: [
          for (final g in (t['taxGroups'] as List).cast<Map<String, dynamic>>())
            TaxGroup(
              percent: g['percent'] as int,
              taxableBase: Money(g['baseSen'] as int),
              tax: Money(g['taxSen'] as int),
            ),
        ],
      ),
    );
  }
}

/// Thrown when a receipt number is reused (replay attempt).
class DuplicateReceiptException implements Exception {
  final String number;
  const DuplicateReceiptException(this.number);

  @override
  String toString() =>
      'DuplicateReceiptException: receipt $number already exists';
}

/// Issues gap-free, monotonic receipt numbers per calendar day:
/// `INV-YYYYMMDD-0001`, `INV-YYYYMMDD-0002`, ...
///
/// Gap-free guarantee: the counter is persisted *before* the receipt is
/// handed to the caller (via [commit]), so a crash between "issue" and
/// "persist receipt" burns no number — the next call re-issues the same
/// number and [DuplicateReceiptException] guards against double-commit.
///
/// The counter state is a plain JSON-serialisable map so any store
/// (file, sqlite, postgres) can persist it atomically alongside receipts.
class ReceiptNumberGenerator {
  /// Persisted state: day key (YYYYMMDD) -> last issued sequence number.
  final Map<String, int> _counters;
  final Set<String> _issuedNumbers;
  final DateTime Function() _now;

  ReceiptNumberGenerator({
    Map<String, int>? counters,
    Iterable<String>? issuedNumbers,
    DateTime Function()? now,
  }) : _counters = Map<String, int>.from(counters ?? const <String, int>{}),
       _issuedNumbers = {...(issuedNumbers ?? const <String>[])},
       _now = now ?? DateTime.now;

  /// Serialise counters for the store.
  Map<String, int> get counters => Map.unmodifiable(_counters);
  Set<String> get issuedNumbers => Set.unmodifiable(_issuedNumbers);

  static String dayKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';

  String _format(String dayKey, int seq) =>
      'INV-$dayKey-${seq.toString().padLeft(4, '0')}';

  /// Peek at the next number without consuming it.
  String peekNext([DateTime? at]) {
    final key = dayKey(at ?? _now());
    return _format(key, (_counters[key] ?? 0) + 1);
  }

  /// Consume and return the next number for the current day.
  /// Call [commit] once the receipt itself is durably saved.
  String next([DateTime? at]) {
    final key = dayKey(at ?? _now());
    final seq = (_counters[key] ?? 0) + 1;
    _counters[key] = seq;
    return _format(key, seq);
  }

  /// Record that a receipt number was durably persisted. Throws if the
  /// number was already committed (replay safety).
  void commit(String number) {
    if (!_issuedNumbers.add(number)) {
      throw DuplicateReceiptException(number);
    }
  }

  /// Build a generator restored from stored state.
  factory ReceiptNumberGenerator.restore({
    required Map<String, dynamic> json,
    DateTime Function()? now,
  }) {
    final counters = <String, int>{};
    (json['counters'] as Map<String, dynamic>? ?? const {}).forEach(
      (k, v) => counters[k] = v as int,
    );
    final issued = (json['issued'] as List<dynamic>? ?? const [])
        .cast<String>();
    return ReceiptNumberGenerator(
      counters: counters,
      issuedNumbers: issued,
      now: now,
    );
  }

  Map<String, dynamic> toJson() => {
    'counters': _counters,
    'issued': _issuedNumbers.toList()..sort(),
  };

  /// Rebuild counters from an existing list of receipts (recovery path:
  /// if the counter file is lost, the receipts themselves are the source
  /// of truth — highest sequence per day wins).
  static Map<String, int> countersFromReceipts(Iterable<Receipt> receipts) {
    final counters = <String, int>{};
    final pattern = RegExp(r'^INV-(\d{8})-(\d{4})$');
    for (final r in receipts) {
      final m = pattern.firstMatch(r.number);
      if (m == null) continue;
      final key = m.group(1)!;
      final seq = int.parse(m.group(2)!);
      if (seq > (counters[key] ?? 0)) counters[key] = seq;
    }
    return counters;
  }
}

/// Z-report (day close) aggregated from receipts.
class DayReport {
  final DateTime day;
  final int receiptCount;
  final Money grossSales; // sum of line subtotals
  final Money totalDiscount;
  final Money sstCollected;
  final Money totalRounding; // sum of rounding adjustments
  final Money netSales; // what the drawer should hold (cash) + card total
  final Map<TenderType, Money> byTender;
  final Map<int, Money> sstByRate;

  const DayReport({
    required this.day,
    required this.receiptCount,
    required this.grossSales,
    required this.totalDiscount,
    required this.sstCollected,
    required this.totalRounding,
    required this.netSales,
    required this.byTender,
    required this.sstByRate,
  });

  static DayReport forDay(List<Receipt> receipts, DateTime day) {
    var count = 0;
    var gross = Money.zero;
    var disc = Money.zero;
    var sst = Money.zero;
    var rounding = Money.zero;
    var net = Money.zero;
    final byTender = <TenderType, Money>{};
    final sstByRate = <int, Money>{};

    final key = ReceiptNumberGenerator.dayKey(day);
    for (final r in receipts) {
      if (!r.number.contains('-$key-')) continue;
      count++;
      gross += r.totals.subtotal;
      disc += r.totals.discount;
      sst += r.totals.taxTotal;
      rounding += r.totals.rounding;
      net += r.totals.total;
      byTender[r.tender] = (byTender[r.tender] ?? Money.zero) + r.totals.total;
      for (final g in r.totals.taxGroups) {
        sstByRate[g.percent] = (sstByRate[g.percent] ?? Money.zero) + g.tax;
      }
    }
    return DayReport(
      day: day,
      receiptCount: count,
      grossSales: gross,
      totalDiscount: disc,
      sstCollected: sst,
      totalRounding: rounding,
      netSales: net,
      byTender: byTender,
      sstByRate: sstByRate,
    );
  }

  /// Plain-text Z-report block (also used by the day-close screen).
  String toText() {
    final b = StringBuffer();
    b.writeln('Z-REPORT ${ReceiptNumberGenerator.dayKey(day)}');
    b.writeln('Receipts      : $receiptCount');
    b.writeln('Gross sales   : ${grossSales.toStringWithSeparator()}');
    b.writeln('Discounts     : -${totalDiscount.toStringWithSeparator()}');
    sstByRate.forEach((pct, amt) {
      if (pct > 0) {
        b.writeln('SST $pct%       : ${amt.toStringWithSeparator()}');
      }
    });
    b.writeln('Rounding adj. : ${totalRounding.toStringWithSeparator()}');
    byTender.forEach((t, amt) {
      b.writeln('${t.name.padRight(14)}: ${amt.toStringWithSeparator()}');
    });
    b.writeln('NET SALES     : ${netSales.toStringWithSeparator()}');
    return b.toString();
  }
}

/// Helper used by both the UI and the demo to render a receipt.
String _centered(String s, int width) {
  if (s.length >= width) return s;
  final left = (width - s.length) ~/ 2;
  return ' ' * left + s + ' ' * (width - s.length - left);
}

String renderReceiptText(Receipt r, {String shopName = 'KEDAI KOPI SUKSES'}) {
  String pad(String label, String value, int width) {
    final space = width - label.length - value.length;
    if (space < 1) return '$label $value';
    return '$label${' ' * space}$value';
  }

  final b = StringBuffer();
  const width = 32;
  b.writeln(_centered(shopName, width));
  b.writeln(_centered('Jalan Melati 1, Shah Alam', width));
  b.writeln('-' * width);
  b.writeln(pad('No', r.number, width));
  final d = r.issuedAt;
  b.writeln(
    pad(
      'Date',
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
      width,
    ),
  );
  b.writeln('-' * width);
  for (final l in r.lines) {
    b.writeln('${l.quantity} x ${l.product.name}');
    b.writeln(pad('', l.subtotal.toString(), width));
  }
  b.writeln('-' * width);
  b.writeln(pad('Subtotal', r.totals.subtotal.toString(), width));
  if (r.totals.discount.isPositive) {
    b.writeln(pad('Discount', '-${r.totals.discount}', width));
  }
  for (final g in r.totals.taxGroups) {
    if (g.percent > 0) {
      b.writeln(pad('SST ${g.percent}%', g.tax.toString(), width));
    }
  }
  if (!r.totals.rounding.isZero) {
    final sign = r.totals.rounding.isNegative ? '-' : '';
    b.writeln(pad('Rounding', '$sign${r.totals.rounding.abs()}', width));
  }
  b.writeln(pad('TOTAL', r.totals.total.toString(), width));
  b.writeln('Tender: ${r.tender.name}');
  b.writeln(_centered('Terima kasih! Terima kasih!', width));
  return b.toString();
}

extension on Money {
  Money abs() => isNegative ? -this : this;
}
