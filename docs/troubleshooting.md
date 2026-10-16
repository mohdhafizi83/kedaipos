# Troubleshooting

Skeleton — add entries as real issues land in
[GitHub Issues](https://github.com/mohdhafizi83/kedaipos/issues).

## Setup & build

### `flutter: command not found`
The Flutter SDK is not on your PATH. Add `<flutter-sdk>/bin` to PATH, or
install from <https://docs.flutter.dev/get-started/install>. Verify with
`flutter --version` (needs 3.47.x stable / Dart 3.13+).

### Version solver fails on `flutter pub get`
You are on an older Flutter. `flutter --version` must show Dart ≥ 3.13
(`environment.sdk: ^3.13.0` in pubspec.yaml). Run `flutter upgrade`.

### `flutter build apk` fails locally
You need an Android SDK (Android Studio is the easy path). CI builds the APK
on every `v*` tag, so you can also just download the prebuilt APK from the
GitHub Release instead of building locally.

## Running the app

### "Cart kosong" and the catalog looks wrong
The UI seeds a demo catalog (`lib/data/catalog_seed.dart`) on first launch
and runs on an in-memory store — edits/reset are expected between sessions
in v1 (see configuration.md → Data storage).

### Receipt totals look "off by a sen"
They aren't — check the Rounding line. Cash tenders round to the nearest
5 sen (Malaysian rule); card tenders never round. All arithmetic is exact
integer sen; if you can produce a wrong total, file an issue with the exact
cart.

### A receipt number seems to have been skipped
Numbers are only consumed by a *successful* checkout. A failed/abandoned
checkout burns nothing. If you genuinely see a gap in persisted state, that
is a bug — include the `pos-state.json` (redact as needed) in the issue.

## Data

### `pos-state.json` won't parse / looks truncated
Should be impossible by design (atomic temp+fsync+rename writes). If it
happens: restore your last daily backup copy (configuration.md → backup).
Please file an issue — a torn file means the atomic-write guarantee broke.

### APK install blocked on Android
Enable "install unknown apps" for the app you opened the APK with
(Settings → Apps → special access). The release APK is unsigned for sideload
use only.

## Where to get help

- [GitHub Issues](https://github.com/mohdhafizi83/kedaipos/issues)
- Security issues: see [SECURITY.md](../SECURITY.md), do not open a public
  issue.
