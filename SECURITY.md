# Security Policy

## Threat model — stated honestly

KedaiPOS is an **offline, single-terminal** point-of-sale. It has **no network
listener, no API, no authentication surface, and no multi-user session
handling**. There is therefore no remote attacker to model: no injection
surface over HTTP, no auth bypass, no SSRF. Pretending otherwise would be
theater. The realistic threats for this shape of software are:

1. **Data corruption** — power cut, disk-full, or app crash mid-write leaves
   the day's receipts in a half-written, unparseable JSON file. At day close
   the drawer cannot be reconciled and the Z-report is wrong.
2. **Invoice-sequence integrity** — Malaysian auditors expect gap-free daily
   invoice numbers. A crash that burns a number, or a replay that reuses one,
   breaks that claim.
3. **Bad input reaching the money math** — a fat-fingered or manipulated
   quantity/price/discount producing a negative or absurd total, or an
   integer overflow silently wrapping to a negative amount.
4. **Secrets in the repository** — a public repo that ever had a credential
   committed is a credential leak, full stop.

## Guarantees (each backed by a test)

### Atomic persistence — crash mid-write cannot corrupt the day

`IoFileGateway.write` (`lib/data/io_gateway.dart`) implements the standard
atomic-save dance:

1. write the **complete** new state to `<path>.tmp` with `flush: true`
   (fsync — bytes are on disk before the Future completes),
2. `rename()` the temp file over the target — atomic within a directory on
   POSIX filesystems.

Any reader — including this app after a hard crash — sees either the complete
old file or the complete new file. Never a torn or truncated file. A failed
write also cleans up its temp file and leaves the in-memory cache unsynced
forward, so memory and disk never disagree optimistically.

Tests: `test/atomic_write_test.dart` (crash injected between fsync and
rename; old file verified intact and valid).

### Receipt sequencing survives failed writes — no gaps, no replays

Checkout order is: issue number → persist receipt + counter in one state
write → commit the number. If the write throws, `PosService` calls
`ReceiptNumberGenerator.rollback(number)`, so the failed attempt burns no
number and the next checkout re-issues the same one. A committed number can
never be committed again (`DuplicateReceiptException`). If the counter state
is ever lost, counters are rebuilt from the receipts themselves (highest
sequence per day wins).

Tests: `test/atomic_write_test.dart` (end-to-end: crash mid-checkout → file
still valid with 1 receipt → restart re-issues the number gap-free),
`test/receipt_store_test.dart` (replay rejection, restart continuation).

### Input validation at the domain boundary

The UI's +/- buttons and any future price-entry field are convenience, not
validation. The domain layer enforces, with runtime throws (not `assert`,
which vanishes in release builds):

- **Quantity**: `CartLine`, `Cart.add`, `Cart.setQuantity` reject zero,
  negative, and oversized (> 100 000) quantities, including merged
  quantities that would exceed the cap.
- **Money**: `Money.parse` rejects `NaN`/`Infinity`/exponent/hex junk,
  malformed separators, >2 decimal places, and — the subtle one — oversized
  values: a digit-length guard runs *before* the `int` multiply, because on
  the Dart VM `int.parse(huge) * 100` wraps around int64 and a negative
  result would slip past a `sen > maxSen` check alone.
- **Discounts**: `PercentDiscount` rejects `<0` or `>100` percent;
  `FlatDiscount` clamps negative amounts to zero so a bogus voucher can
  never *increase* the bill.

Tests: `test/validation_test.dart`, `test/money_test.dart`.

### Secret hygiene

CI runs **gitleaks** (SHA-pinned) over full history on every push/PR, and all
third-party GitHub Actions are pinned to full commit SHAs, not mutable tags.
The app itself requires zero credentials — `dart run bin/demo.dart` works
with no secrets by design, so there is nothing to steal at runtime.

## Explicitly out of scope

- **MyInvois / e-invoice**: not implemented. When it lands it will be an
  adapter behind the existing `PosRepository` seam; its threat model (API
  credentials, TLS, token storage) will need its own security review at that
  time.
- **Multi-user / multi-terminal hardening**: file permissions on the state
  file assume a single trusted operator on the machine. Multi-terminal
  breaks the single-writer assumption and needs a transactional store before
  any concurrency guarantees can be claimed.
- **Network attack surface**: there is none to harden. If KedaiPOS ever gains
  a server component, this document must be rewritten with an endpoint-level
  threat model before that code ships.
- **Physical security**: a cashier with physical access to the machine can
  edit the JSON file directly. Filesystem permissions and OS-level user
  accounts are the mitigation, outside this app.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository
(mohdhafizi83/kedaipos → Security → Report a vulnerability). Expect an
acknowledgement within 7 days.
