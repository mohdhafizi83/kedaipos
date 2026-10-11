# KedaiPOS

[![CI](https://github.com/mohdhafizi83/kedaipos/actions/workflows/ci.yml/badge.svg)](https://github.com/mohdhafizi83/kedaipos/actions/workflows/ci.yml)

An offline-first cashier POS for small Malaysian kedai (warung / cafe / mini-market) — built around the part most POS demos get wrong: **money**.

Every ringgit value in this codebase is an exact integer count of sen. SST is computed on the discounted base (the correct order for Malaysian tax). Cash totals round to the nearest 5 sen the way cashiers actually do it. Receipt numbers are gap-free per day, survive restarts, and refuse replays. All of it is pure Dart, fully unit-tested (50 tests), with zero third-party dependencies.

## Why most POS demos are toys

1. **Float money bugs.** `0.1 + 0.2 != 0.3` in IEEE-754. A cart of RM3.20 × 3 computed with `double` can land on 959.99999 sen and the till is one sen short at close. Most tutorials store prices as `double` and format with `toStringAsFixed(2)`, which papers over the error instead of removing it.
2. **Tax computed before discount.** SST must be charged on the consideration *actually paid*. Tax-on-gross overcharges the customer whenever a discount applies — a real compliance bug, not a rounding nit.
3. **No receipt sequencing.** Real cashiers need gap-free, monotonic invoice numbers per day (LHDN audit expectation). Demo apps use `DateTime.now().millisecondsSinceEpoch` or UUIDs, which are unsorted and un-auditable.
4. **No cash rounding.** Malaysian cash payments round to the nearest 5 sen (halves away from zero); card payments never round. Getting this wrong means the drawer never balances.

## What a Malaysian cashier actually needs

- **SST mix**: prepared food/drinks at 8% service tax, packaged essentials (bottled water, instant noodles, canned/sachet goods) at 0% — per item, configurable.
- **5-sen cash rounding** shown as its own receipt line, so the drawer reconciles exactly.
- **Gap-free invoice numbers** (`INV-YYYYMMDD-0001`) that continue correctly after an app restart or crash.
- **Z-report** at day close: gross sales, discounts, SST collected per rate, rounding adjustment total, cash vs card split.

## Design notes

**Integer sen everywhere.** `Money` stores an `int sen`. Parsing (`"RM1,234.56"`) and formatting are pure string arithmetic — `double` is structurally unreachable for money. Percentage math goes through `multiplyRatio(8, 100)`: integer multiply then exact remainder comparison, so 8% SST rounds half-up deterministically.

**Discount before tax.** `Cart.taxableBase = subtotal - discount`. The discount is allocated pro-rata across lines with a largest-remainder method in exact integer arithmetic, so per-line discounted bases always sum back to the taxable base — no sen is lost or double-taxed. A test asserts the tax on a discounted cart is 186 sen, not the 207 sen you'd get from tax-on-gross.

**Rounding only at cash tender.** `TaxEngine.price(cart, tender:)` applies `roundToNearest(5)` (halves away from zero) only for `TenderType.cash`. Card and e-wallet totals keep exact sen. The rounding delta is a first-class receipt line and is aggregated in the Z-report, because the drawer physically gains/loses that money.

**Gap-free sequence + replay safety.** `ReceiptNumberGenerator` keeps a per-day counter. The order of operations at checkout is: issue number → persist receipt + counter in one state write → commit the number. If the write fails, the number is not committed and gets re-issued — no gaps. A committed number can never be committed again (`DuplicateReceiptException`), and counters can be rebuilt from the receipts themselves if the counter state is ever lost.

**JSON-file store is honest for one terminal.** `JsonFileStore` is pure Dart behind a `FileGateway` port (no `dart:io` import in `lib/`), so the same store code compiles for web and desktop and is trivially testable with a fake gateway. A single JSON file rewritten atomically is genuinely appropriate for a single-terminal warung setup. Multi-terminal would need per-terminal sequence partitions (or a DB sequence) and row-level transactions — that's exactly where Postgres slots in: implement `PosRepository` over Postgres, everything above `lib/data/` is unchanged.

**Zero third-party dependencies.** `pubspec.yaml` depends only on the Flutter SDK. State management is `setState` + a plain `PosService` — appropriate at this size, and it keeps the domain layer importable by a CLI (`bin/demo.dart`) with no Flutter binding.

## Architecture

```
lib/
  domain/        pure Dart, zero Flutter imports
    money.dart         Money (int sen), exact parse/format/multiplyRatio/roundToNearest
    cart.dart          Product, CartLine, Cart, Flat/Percent discounts
    tax_engine.dart    TaxEngine: SST groups, pro-rata discount, cash rounding
    receipt.dart       Receipt, ReceiptNumberGenerator, DayReport (Z-report)
  data/
    store.dart         PosRepository port + JsonFileStore (FileGateway-injected) + InMemoryStore
    catalog_seed.dart  12 realistic MY items with per-item SST flags
  app/
    pos_service.dart   checkout orchestration (shared by UI and CLI demo)
  ui/            Material 3: POS pad, receipt preview, day-close Z-report
bin/
  demo.dart      zero-credential deterministic 6-order trading day
```

## Run the demo (zero credentials, deterministic)

```bash
dart run bin/demo.dart
```

Sample output (first receipt + Z-report; full run prints all 6 receipts):

```text
======================================
       KEDAI KOPI SUKSES
   Jalan Melati 1, Shah Alam
--------------------------------
No             INV-20261011-0001
Date            11/10/2026 09:30
--------------------------------
2 x Nasi Lemak
                         RM13.00
1 x Teh Tarik
                          RM3.00
--------------------------------
Subtotal                 RM16.00
SST 8%                    RM1.28
Rounding                  RM0.02
TOTAL                    RM17.30
Tender: cash
  Terima kasih! Terima kasih!

======================================
Z-REPORT 20261011
Receipts      : 6
Gross sales   : RM114.00
Discounts     : -RM3.59
SST 8%       : RM6.33
Rounding adj. : -RM0.02
cash          : RM93.70
card          : RM23.02
NET SALES     : RM116.72

--------------------------------------
After restart, next receipt number would be: INV-20261011-0007
(gap-free: counter restored from kedaipos_demoXXXXXX/pos-state.json)
```

The demo writes a real JSON state file to a temp dir, runs six orders (mixed SST, 10% discount, flat RM1 voucher, a cash sale that rounds up, a card sale that must not round), then reopens the store to prove the receipt sequence continues gap-free after a simulated restart.

## Run the app

```bash
flutter run -d chrome     # web
flutter test              # 50 tests, no network
```

## Tests (50, all offline)

- **Money** (18): parse/format edge cases, thousands separators, malformed input rejection, negative amounts, the `0.1 + 0.2` float trap, `multiplyRatio` half-up table, 5-sen rounding table for every sen digit 0–9 including exact halves.
- **Cart + TaxEngine** (15): add/merge/setQuantity/remove invariants, discount clamping, SST mix (8% + 0% groups), discount-before-tax ordering (asserts 186 sen vs the wrong 207 sen), pro-rata allocation sums exactly, cash vs card rounding behaviour.
- **Receipt + store** (11): format/padding, per-day rollover, peek non-consuming, replay rejection, JSON roundtrip restart, counter recovery from receipts, `total == lines − discount + tax + rounding` identity.
- **Property-style** (2): 2 000 seeded-random carts — the receipt identity and 5-sen grid hold exactly on every one; SST drift vs ideal ≤ 1 sen per group.
- **Widget** (4): tap product updates cart total, checkout navigates to receipt, day-close shows SST, discount button changes totals.

CI runs `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test`, `flutter build web --release`, and executes the demo on every push (Flutter 3.47.7, ubuntu).

## Honest limitations

- **Single terminal.** One JSON state file, one writer. Multi-terminal needs per-terminal sequence partitions and a real transactional store (the `PosRepository` port is the seam).
- **No printer integration.** The receipt is a monospace text block (same renderer in app and CLI); ESC/POS or thermal SDK integration is deliberately out of scope.
- **No MyInvois e-invoice.** Malaysia's mandatory e-invoice rollout is the obvious next step: a `MyInvoisAdapter` behind the same repository seam, mapping `Receipt` → consolidated JSON with the LHDN tax-code split per rate group.
- **Mobile builds not CI-proven.** The repo declares Android + iOS platforms, but CI has no Android SDK; the web release build is the CI proof of compilability. `flutter test` covers all logic. APK builds need Android SDK locally.
- SST rates/flags are simplified per-item (8% / 0%); real SST has scope nuances (service vs sales tax, registration thresholds) that a production system must model per business registration.

## License

MIT
