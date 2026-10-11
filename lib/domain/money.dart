/// Exact money arithmetic in integer sen (1 RM = 100 sen).
///
/// No `double` is ever used for money anywhere in this codebase. Every
/// value that represents currency is an `int` count of sen; parsing and
/// formatting are the only places a decimal string is touched, and both
/// go through exact string manipulation — never `double.parse`.
library;

/// Thrown when a string cannot be parsed as a money amount.
class MoneyParseException implements Exception {
  final String input;
  const MoneyParseException(this.input);

  @override
  String toString() => 'MoneyParseException: cannot parse "$input" as money';
}

/// An immutable monetary value stored as an exact integer number of sen.
class Money implements Comparable<Money> {
  /// Amount in sen (can be negative for discounts/refunds).
  final int sen;

  const Money(this.sen);

  static const Money zero = Money(0);

  /// Construct from a whole ringgit value, e.g. `Money.rm(6)` == RM6.00.
  const Money.rm(int ringgit) : sen = ringgit * 100;

  /// Largest representable amount (guard against absurd inputs).
  static const int maxSen = 1 << 53;

  /// Parse a decimal string exactly: `"6.50"`, `"RM1,234.56"`, `"-3.2"`,
  /// `"1.005"` (rejected — more than 2 decimal places), `"1,23"` (rejected —
  /// comma must be a thousands separator).
  ///
  /// Implemented with pure string arithmetic so `0.1 + 0.2` style float bugs
  /// are structurally impossible.
  static Money parse(String input) {
    var s = input.trim();
    if (s.isEmpty) {
      throw const MoneyParseException('');
    }
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1).trim();
    } else if (s.startsWith('+')) {
      s = s.substring(1).trim();
    }
    // Strip a leading currency symbol/word (RM, rm) after the sign.
    if (s.length >= 2 && (s.startsWith('RM') || s.startsWith('rm'))) {
      s = s.substring(2).trim();
    }
    if (s.isEmpty) {
      throw MoneyParseException(input);
    }

    // Validate thousands separators: commas only allowed as groups of 3
    // digits from the right of the integer part.
    final commaCount = ','.allMatches(s).length;
    if (commaCount > 0) {
      final dotIndex = s.indexOf('.');
      final intPart = dotIndex == -1 ? s : s.substring(0, dotIndex);
      final fracPart = dotIndex == -1 ? '' : s.substring(dotIndex + 1);
      if (!RegExp(r'^\d{1,3}(,\d{3})*$').hasMatch(intPart) ||
          (fracPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracPart))) {
        throw MoneyParseException(input);
      }
      s = intPart.replaceAll(',', '') + (fracPart.isEmpty ? '' : '.$fracPart');
    }

    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (match == null) {
      throw MoneyParseException(input);
    }
    final intPart = match.group(1)!;
    final fracRaw = match.group(2) ?? '';
    final frac = fracRaw.padRight(2, '0');
    // Reject values that would silently overflow. The digit-length check
    // runs BEFORE the multiply: on the VM, `int.parse(huge) * 100` wraps
    // around to a negative int64, and a negative result would sneak past a
    // `sen > maxSen` check alone.
    if (intPart.length > 15) {
      throw MoneyParseException(input);
    }
    final sen = int.parse(intPart) * 100 + int.parse(frac);
    if (sen > maxSen) {
      throw MoneyParseException(input);
    }
    return Money(negative ? -sen : sen);
  }

  /// Parse a string but return null instead of throwing on bad input.
  static Money? tryParse(String input) {
    try {
      return parse(input);
    } on MoneyParseException {
      return null;
    }
  }

  Money operator +(Money other) => Money(sen + other.sen);
  Money operator -(Money other) => Money(sen - other.sen);
  Money operator *(int factor) => Money(sen * factor);
  Money operator -() => Money(-sen);

  /// Multiply by a rational `numerator/denominator` with a chosen rounding
  /// rule. Used for percentage math (tax, discounts) without ever touching
  /// floating point: `amount.multiplyRatio(8, 100)` == 8% of amount.
  ///
  /// [halfUp] uses round-half-away-from-zero on the exact remainder, which
  /// matches Malaysian commercial practice for SST computation.
  Money multiplyRatio(int numerator, int denominator, {bool halfUp = true}) {
    if (denominator == 0) {
      throw ArgumentError('denominator must not be zero');
    }
    final product = sen * numerator;
    if (!halfUp) {
      return Money(product ~/ denominator);
    }
    // Round half away from zero, exactly, using integer arithmetic.
    final negative = product < 0;
    final abs = negative ? -product : product;
    final q = abs ~/ denominator;
    final r = abs % denominator;
    final rounded = (r * 2 >= denominator) ? q + 1 : q;
    return Money(negative ? -rounded : rounded);
  }

  /// Round to the nearest multiple of [stepSen] (e.g. 5 for Malaysian cash
  /// rounding), halves away from zero. Exact integer arithmetic.
  Money roundToNearest(int stepSen) {
    if (stepSen <= 0) {
      throw ArgumentError('stepSen must be positive');
    }
    final negative = sen < 0;
    final abs = negative ? -sen : sen;
    final q = abs ~/ stepSen;
    final r = abs % stepSen;
    final rounded = (r * 2 >= stepSen) ? q + 1 : q;
    return Money(negative ? -rounded * stepSen : rounded * stepSen);
  }

  bool operator <(Money other) => sen < other.sen;
  bool operator >(Money other) => sen > other.sen;
  bool operator <=(Money other) => sen <= other.sen;
  bool operator >=(Money other) => sen >= other.sen;

  bool get isZero => sen == 0;
  bool get isNegative => sen < 0;
  bool get isPositive => sen > 0;

  /// Format as `RM12.30` (always 2 decimals, no thousands separator).
  @override
  String toString() {
    final negative = sen < 0;
    final abs = negative ? -sen : sen;
    final ringgit = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}RM$ringgit.$frac';
  }

  /// Format with thousands separators: `RM1,234.50`.
  String toStringWithSeparator() {
    final negative = sen < 0;
    final abs = negative ? -sen : sen;
    final ringgit = (abs ~/ 100).toString();
    final frac = (abs % 100).toString().padLeft(2, '0');
    final grouped = ringgit.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '${negative ? '-' : ''}RM$grouped.$frac';
  }

  @override
  int compareTo(Money other) => sen.compareTo(other.sen);

  @override
  bool operator ==(Object other) => other is Money && other.sen == sen;

  @override
  int get hashCode => sen.hashCode;
}
