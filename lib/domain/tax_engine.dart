/// SST (Sales & Service Tax) computation and Malaysian cash rounding.
///
/// Rules encoded here:
/// * SST is computed per tax-rate group on the discounted line subtotal
///   (discount-before-tax), rounded half-up per group to the nearest sen.
/// * Cash tenders are rounded to the nearest 5 sen (halves away from zero);
///   the rounding difference is shown as its own receipt line. Card
///   payments are never rounded.
library;

import 'cart.dart';
import 'money.dart';

/// Tax breakdown for one rate group (e.g. all 8% lines).
class TaxGroup {
  final int percent;
  final Money taxableBase;
  final Money tax;
  const TaxGroup({
    required this.percent,
    required this.taxableBase,
    required this.tax,
  });
}

/// How the customer is paying — decides whether 5-sen rounding applies.
enum TenderType { cash, card, eWallet }

/// Result of pricing a cart: everything a receipt needs to show.
class Totals {
  final Money subtotal;
  final Money discount;
  final List<TaxGroup> taxGroups;
  final Money taxTotal;
  final Money subtotalWithTax;

  /// Rounding applied to reach a 5-sen grid (cash only; zero otherwise).
  final Money rounding;
  final Money total;

  const Totals({
    required this.subtotal,
    required this.discount,
    required this.taxGroups,
    required this.taxTotal,
    required this.subtotalWithTax,
    required this.rounding,
    required this.total,
  });
}

class TaxEngine {
  const TaxEngine();

  /// Compute tax per rate group for a cart.
  ///
  /// Discount is distributed pro-rata across lines by subtotal share, then
  /// tax is computed on each line's discounted base and summed per group.
  /// Pro-rata distribution uses exact integer arithmetic with the remainder
  /// given to the largest line, so the discounted bases always sum exactly
  /// to `taxableBase` (no lost sen, no double-counted sen).
  List<TaxGroup> taxBreakdown(Cart cart) {
    final subtotal = cart.subtotal;
    final discount = cart.discountAmount;
    final groups = <int, ({Money base, Money tax})>{};

    if (cart.isEmpty) {
      return const [];
    }

    // Pro-rata discount allocation (exact, remainder to largest line).
    final shares = _allocateDiscount(cart, discount);

    for (var i = 0; i < cart.lines.length; i++) {
      final line = cart.lines[i];
      final base = shares[i];
      final percent = line.product.taxPercent;
      final tax = base.multiplyRatio(percent, 100);
      final existing = groups[percent];
      groups[percent] = (
        base: (existing?.base ?? Money.zero) + base,
        tax: (existing?.tax ?? Money.zero) + tax,
      );
    }

    final result = groups.entries.map((e) {
      return TaxGroup(
        percent: e.key,
        taxableBase: e.value.base,
        tax: e.value.tax,
      );
    }).toList()..sort((a, b) => a.percent.compareTo(b.percent));
    // Guard: subtotal must equal sum of bases + discount (invariant test).
    assert(
      subtotal ==
          discount + groups.values.fold(Money.zero, (s, g) => s + g.base),
    );
    return result;
  }

  /// Exact pro-rata allocation of [discount] across cart lines.
  List<Money> _allocateDiscount(Cart cart, Money discount) {
    final subtotal = cart.subtotal;
    if (discount.isZero || subtotal.isZero) {
      return cart.lines.map((l) => l.subtotal).toList();
    }
    final result = <Money>[];
    var allocated = 0;
    // Floor each share, track remainders for largest-remainder method.
    final remainders = <int, int>{};
    for (var i = 0; i < cart.lines.length; i++) {
      final lineSen = cart.lines[i].subtotal.sen;
      final share = lineSen * discount.sen ~/ subtotal.sen;
      result.add(Money(lineSen - share));
      remainders[i] = (lineSen * discount.sen) % subtotal.sen;
      allocated += share;
    }
    // Distribute the leftover sen (discount.sen - allocated) one at a time
    // to lines with the largest remainders.
    var leftover = discount.sen - allocated;
    final order = remainders.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    for (final entry in order) {
      if (leftover <= 0) break;
      result[entry.key] = result[entry.key] - Money(1);
      leftover--;
    }
    return result;
  }

  /// Full pricing for a cart given a tender type.
  Totals price(Cart cart, {TenderType tender = TenderType.cash}) {
    final subtotal = cart.subtotal;
    final discount = cart.discountAmount;
    final groups = taxBreakdown(cart);
    final taxTotal = groups.fold(Money.zero, (s, g) => s + g.tax);
    final withTax = subtotal - discount + taxTotal;

    // Malaysian cash rounding: nearest 5 sen, only for cash tenders.
    final Money rounding;
    final Money total;
    if (tender == TenderType.cash) {
      final rounded = withTax.roundToNearest(5);
      rounding = rounded - withTax;
      total = rounded;
    } else {
      rounding = Money.zero;
      total = withTax;
    }

    return Totals(
      subtotal: subtotal,
      discount: discount,
      taxGroups: groups,
      taxTotal: taxTotal,
      subtotalWithTax: withTax,
      rounding: rounding,
      total: total,
    );
  }
}
