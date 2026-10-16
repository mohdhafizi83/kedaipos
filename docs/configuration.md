# Configuration

Honest answer first: **v1.0.0 has no settings file and no runtime
configuration.** Everything that varies per shop lives in code at the seams
listed below. This document tells you exactly what is configurable today,
what is deliberately not, and how to back up data.

## What is configurable today

| Thing | Where | How to change |
|---|---|---|
| Product catalog (names, prices in sen, SST 8%/0% per item) | `lib/data/catalog_seed.dart` | Edit the seed list, or replace the store contents (`products` array in `pos-state.json`) |
| SST rate model | `lib/domain/tax_engine.dart` | Per-item `taxPercent`; only 8%/0% mix is modelled (see README limitations) |
| Cash rounding grid | `lib/domain/money.dart` | 5-sen rounding is fixed by Malaysian law; change only if the law changes |
| Shop name/address on receipt | `lib/domain/receipt.dart` renderer | Edit the header block |
| Receipt number prefix/format | `lib/domain/receipt.dart` | `INV-YYYYMMDD-NNNN`, per-day rollover |

There are no secrets, no env vars, and no network endpoints — hence no
`.env.example`.

## Receipt printer pairing — the honest status

**There is no printer pairing in v1.0.0.** No Bluetooth, no USB, no ESC/POS
SDK. This is a deliberate scope decision (see README → Honest limitations).

What works today:

- The receipt is a plain monospace text block, identical in the app and the
  CLI demo.
- On Android you can select/copy the receipt text and send it to any
  ESC/POS printing utility or shared network printer that accepts raw text
  (58 mm printers wrap at 32 columns; the renderer already fits).

Planned seam: an `IoGateway`-style `PrinterGateway` port so a Bluetooth/USB
ESC/POS implementation can be injected without touching domain code.

## Data storage & backup

Two persistence modes exist:

1. **Flutter UI (current):** runs on `InMemoryStore`. Data lives only for the
   app session — closing the app discards the day's receipts. This is the
   single biggest v1 limitation; wiring `JsonFileStore` into the mobile
   target is the next milestone.
2. **File mode (`JsonFileStore` + `IoFileGateway`):** used by the CLI demo
   and tests. All state (products, receipts, counters) is one JSON file,
   e.g. `pos-state.json`.

Backing up file-mode data:

```bash
cp pos-state.json /safe/place/pos-state-$(date +%F).json
```

That is the entire backup procedure — one file, copy it. Writes are atomic
(temp + fsync + rename), so a copy taken at any moment, even mid-save, is
always a complete older-or-newer file, never a torn one. Restoring is copying
it back.

**Backup cadence that matches the audit requirement (gap-free receipts):**
copy the file at least once per trading day, ideally right after the Z-report.
Keep at least one generation per day so a bad restore can never re-issue an
already-used invoice number (replay rejection also guards this within a file).

## Multi-terminal / server mode

Not supported. One state file, one writer. The `PosRepository` port in
`lib/data/store.dart` is the seam where a real transactional backend would
attach.
