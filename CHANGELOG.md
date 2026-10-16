# Changelog

All notable changes to KedaiPOS are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-11

Initial release: offline-first cashier POS for small Malaysian kedai.

### Added

- **Exact sen math** — all money is integer sen end-to-end; no floating-point
  currency. Parse/format with thousands separators and malformed-input
  rejection (NaN/Infinity/hex junk, int64-wraparound guard).
- **SST engine** — per-item 8% / 0% tax groups, discount-before-tax ordering,
  pro-rata allocation that sums exactly to the discount.
- **5-sen cash rounding** — Malaysian rounding grid for cash tenders only;
  card tenders are never rounded.
- **Gap-free receipt numbering** — per-day invoice sequence (`INV-YYYYMMDD-NNNN`)
  with replay rejection; a failed checkout burns no number, and the sequence
  survives restarts.
- **Atomic persistence** — `JsonFileStore` writes via temp file + fsync +
  atomic rename, so a crash mid-write leaves the previous complete file,
  never a torn one (crash-injection tested).
- **POS UI (Flutter, Material 3)** — product grid, cart with quantity
  controls, percent/flat discounts, cash/card checkout, receipt screen,
  day-close Z-report. Material 3 with `ColorScheme.fromSeed(#6366F1)` and
  system dark-mode support.
- **Zero-credential CLI demo** — `dart run bin/demo.dart` runs a full
  deterministic trading day through the same service the app uses and proves
  gap-free restart against a real JSON file.
- **63 offline tests** — money, cart/tax, receipt/store, atomic writes,
  input validation, property-style invariants (2 000 seeded carts), and
  widget tests.
- **CI** — analyze + format + test + web release build + demo run on every
  push; SHA-pinned actions; gitleaks history scan.
- **Release workflow** — tag `v*` builds a web release zip and Android APK
  and attaches both to the GitHub Release.

### Known limitations

- Single terminal, one JSON state file; the Flutter UI currently runs on an
  in-memory store (persistence layer is proven in the CLI demo and tests).
- No thermal-printer integration (receipt is a monospace text block).
- No MyInvois e-invoice adapter yet.
