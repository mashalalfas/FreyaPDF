<p align="center">
  <img src="assets/logo/FREYA PDF.png" width="120" alt="Freya PDF logo" />
</p>

<h1 align="center">Freya PDF</h1>

<p align="center">
  A clean, fast, ad-free PDF reader for Android with end-to-end encryption,
  annotations, and privacy-first features.
  <br />
  <br />
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter" />
  <img alt="Android" src="https://img.shields.io/badge/Android-API_21%2B-3ddc84?logo=android" />
  <img alt="CI" src="https://github.com/mashalalfas/FreyaPDF/actions/workflows/ci.yml/badge.svg" />
  <img alt="Version" src="https://img.shields.io/badge/version-1.2.0-blueviolet" />
</p>

---

## About

Freya PDF is a private, offline-first PDF reader. Your files stay on your device —
data is never collected, there are no accounts, and no backend is required.
Protected documents are encrypted with AES-256-GCM and derived keys (PBKDF2) so
they can't be read without your passphrase.

## Features

- **PDF viewing** — native annotation rendering, pinch-zoom, page navigation (via `pdfrx`)
- **End-to-end encryption** — AES-256-GCM with PBKDF2 key derivation (`.pdf.enc` format)
- **Secure folder** — dedicated encrypted directory for sensitive files
- **Text search** — bounded PDF text search with match navigation (find next/previous)
- **Annotations** — persistent text + rectangle highlights with full CRUD and color picker
- **Bookmarks** — per-document bookmarking with rename and panel view
- **Remembered PDF passwords** — optionally unlock standard protected PDFs and remember the password securely (stored only in platform secure storage, keyed by path hash)
- **App lock** — PIN lock screen with biometric (fingerprint/face/iris) fallback
- **Tags** — 8-color palette, filter bar, and management screen
- **Dark mode** — system-aware with manual toggle
- **Outline / TOC** — PDF table of contents navigation
- **Thumbnail grid** — visual page overview
- **Text selection** — select and copy text from pages
- **Continuous scroll** — alternative to page-by-page reading
- **File management** — sort by name/date/size, search, save-to-directory, recent files, recursive multi-folder scanning
- **SVG preview** — vector file support
- **"Open with" support** — native Android intent handler
- **Auto-update** — in-app update checks via GitHub Releases
- **Passphrase strength** — visual strength indicator when unlocking encrypted docs

## Stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.x (Dart) |
| State management | Provider / ChangeNotifier |
| PDF rendering | pdfrx (native annotations) |
| Encryption | AES-256-GCM + PBKDF2 (`encrypt`, `pointycastle`) |
| Secure storage | `flutter_secure_storage` (keystore/Keychain) |
| Biometrics | `local_auth` |
| Persistence | `shared_preferences`, file system |
| Updates | GitHub Releases API (`http`) |
| CI | GitHub Actions (analyze + test) |

## Getting started

### Prerequisites

- Flutter 3.x (stable channel)
- Android SDK (API 21+)
- A connected Android device or emulator

### Build

The app embeds the current git commit hash at build time (shown in
**Settings → About → Commit**). Always build through the wrapper so the hash is injected:

```bash
./tool/build_apk.sh release                  # build a release APK
./tool/build_apk.sh profile --install        # build a profile APK and install on a device
./tool/build_apk.sh debug                    # build a debug APK
```

## Testing

```bash
flutter analyze
flutter test --concurrency=1
```

Current status: **`flutter analyze` clean, 392 tests passing** (4 intentional headless skips)
across 28 test files — services, providers, models, widget flows, and security (encryption, app lock, biometrics, PDF password memory).

## Documentation

| Doc | Purpose |
|---|---|
| [`docs/clean/architecture.md`](docs/clean/architecture.md) | Architecture and module overview |
| [`docs/clean/roadmap.md`](docs/clean/roadmap.md) | Roadmap and plan status |
| [`docs/clean/search.md`](docs/clean/search.md) | PDF search architecture, limits, and resolved ANR |
| [`KNOWLEDGE_MAP.md`](KNOWLEDGE_MAP.md) | Codebase knowledge graph |

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `flutter analyze` and the
test suite on every push/PR to `master`.

## Website

The Freya PDF landing page is deployed via the `gh-pages` branch:
https://mashalalfas.github.io/FreyaPDF/

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

This project handles encrypted documents and stores secrets. If you find a
security vulnerability, please read [SECURITY.md](SECURITY.md) and report it
privately — do not open a public issue.

## License

Proprietary. All rights reserved. See [LICENSE](LICENSE).
