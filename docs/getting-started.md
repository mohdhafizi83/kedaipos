# Getting started

KedaiPOS is offline-first: no accounts, no network calls, no API keys. You
need only the Flutter SDK.

## Prerequisites

- **Flutter 3.47.x stable** (Dart 3.13+). Tested with 3.47.7.
  Install: <https://docs.flutter.dev/get-started/install>
- No Android Studio / Xcode needed unless you want to build native binaries
  locally — the web target works with just the SDK.

## Run from source

```bash
git clone https://github.com/mohdhafizi83/kedaipos.git
cd kedaipos
flutter pub get

# Full test suite (63 tests, all offline)
flutter test

# Zero-credential CLI demo: a deterministic trading day + Z-report
dart run bin/demo.dart

# Launch the app in Chrome
flutter run -d chrome
```

## Build the web app

```bash
flutter build web --release   # output: build/web/
python3 -m http.server -d build/web 8080   # or any static server
```

Open <http://localhost:8080>. Any static host works (GitHub Pages, nginx,
`flutter run -d web-server`).

## Install a built APK on Android

Each GitHub Release (tag `v*`) attaches prebuilt artifacts:

- `kedaipos-android-vX.Y.Z.apk` — release APK
- `kedaipos-web-vX.Y.Z.zip` — static web build

To install the APK:

1. Download the `.apk` from the [Releases
   page](https://github.com/mohdhafizi83/kedaipos/releases) onto the phone.
2. Android will ask to allow installs from unknown sources for your
   browser/file manager — confirm once.
3. Open the file and install. No Play Store, no account, no permissions beyond
   storage-free operation (the app makes no network requests).

> The APK is an unsigned release build: fine for sideloading on your own
> devices. Production Play distribution needs your own signing key.

## Web demo without building

If you just want to see what it does without installing anything:

```bash
dart run bin/demo.dart
```

It prints six receipts (mixed SST, discounts, cash rounding) and a Z-report
through the exact same service the UI uses, then proves the receipt sequence
continues gap-free after a simulated restart.

## Where to go next

- [configuration.md](configuration.md) — what is configurable, printer
  reality-check, and how to back up data.
- [troubleshooting.md](troubleshooting.md) — common failures and fixes.
