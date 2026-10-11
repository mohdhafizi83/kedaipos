/// Cart aggregate: line items, quantities, discounts. Pure Dart — no Flutter.
library;

import 'money.dart';

/// A sellable product. [taxRate] is expressed as basis-point-free integer
/// numerator over 100 (e.g. 8 => SST 8%, 0 => zero-rated essentials).
class Product {
  final String id;
  final String name;
  final Money unitPrice;

  /// SST percentage numerator (8 => 8%, 0 => exempt).
  final int taxPercent;

  const Product({
    required this.id,
    required this.name,
    required this.unitPrice,
    this.taxPercent = 8,
  });
}

/// One line in a cart: a product with a quantity.
class CartLine {
  final Product product;
  final int quantity;

  CartLine({required this.product, required this.quantity})
    : assert(quantity > 0, 'quantity must be positive');

  /// Line total before tax: unit price * qty (exact integer multiply).
  Money get subtotal => product.unitPrice * quantity;

  CartLine withQuantity(int newQty) =>
      CartLine(product: product, quantity: newQty);
}

/// The kind of discount applied to a cart.
sealed class Discount {
  const Discount();
  Money applyTo(Money base);
}

/// Flat amount off the cart total, e.g. RM1.00 voucher.
class FlatDiscount extends Discount {
  final Money amount;
  const FlatDiscount(this.amount);

  @override
  Money applyTo(Money base) => amount > base ? base : amount; // never below zero
}

/// Percentage off, e.g. 10% staff discount. Exact rational multiply.
class PercentDiscount extends Discount {
  final int percent;
  const PercentDiscount(this.percent);

  @override
  Money applyTo(Money base) => base.multiplyRatio(percent, 100);
}

/// A cart being built by the cashier.
class Cart {
  final List<CartLine> _lines = [];
  Discount? _discount;

  /// Snapshot of current lines (immutable view).
  List<CartLine> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;
  int get lineCount => _lines.length;
  int get totalQuantity => _lines.fold(0, (sum, l) => sum + l.quantity);

  Discount? get discount => _discount;

  /// Add [quantity] of [product]; merges with an existing line if present.
  void add(Product product, {int quantity = 1}) {
    if (quantity <= 0) {
      throw ArgumentError('quantity must be positive');
    }
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].product.id == product.id) {
        _lines[i] = _lines[i].withQuantity(_lines[i].quantity + quantity);
        return;
      }
    }
    _lines.add(CartLine(product: product, quantity: quantity));
  }

  /// Set the exact quantity of a product's line; qty <= 0 removes the line.
  void setQuantity(String productId, int quantity) {
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].product.id == productId) {
        if (quantity <= 0) {
          _lines.removeAt(i);
        } else {
          _lines[i] = _lines[i].withQuantity(quantity);
        }
        return;
      }
    }
  }

  /// Remove a whole line by product id. Returns true if something was removed.
  bool removeLine(String productId) {
    final before = _lines.length;
    _lines.removeWhere((l) => l.product.id == productId);
    return _lines.length < before;
  }

  void applyDiscount(Discount discount) => _discount = discount;
  void clearDiscount() => _discount = null;
  void clear() {
    _lines.clear();
    _discount = null;
  }

  /// Sum of line subtotals before discount and tax.
  Money get subtotal {
    var total = Money.zero;
    for (final l in _lines) {
      total = total + l.subtotal;
    }
    return total;
  }

  /// Discount amount actually applied (clamped to subtotal).
  Money get discountAmount {
    final d = _discount;
    return d == null ? Money.zero : d.applyTo(subtotal);
  }

  /// Subtotal after discount, before tax. Discount is applied BEFORE tax —
  /// SST is charged on the consideration actually paid, per Royal Malaysian
  /// Customs Group practice.
  Money get taxableBase => subtotal - discountAmount;
}
