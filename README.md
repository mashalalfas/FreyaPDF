# Feya PDF

A clean, fast, ad-free PDF reader for Android with E2E encryption, annotation support, and privacy features.

## Features

- **PDF viewing** with pdfrx — native annotation rendering, pinch-zoom, page navigation
- **E2E encryption** — AES-256-GCM, PBKDF2 key derivation, .pdf.enc format
- **Secure folder** — dedicated encrypted directory for sensitive files
- **Tag system** — 8-color palette, filter bar, management screen
- **Text highlighting** — persistent highlights per document, full CRUD with color picker
- **App lock** — PIN-based lock screen with biometric fallback
- **Biometric unlock** — face, fingerprint, and iris authentication via local_auth
- **Text search** — full PDF text search with result navigation (find next/previous)
- **Dark mode** — system-aware and manual toggle for night reading
- **Thumbnail grid** — visual page overview for quick navigation
- **Text selection** — select and copy text from PDF pages
- **SVG preview** — vector file support via flutter_svg
- **Outline/TOC** — PDF table of contents sidebar for document structure
- **Continuous scroll** — alternative to page-by-page reading
- **Passphrase strength** — visual indicator when unlocking encrypted docs
- **File management** — sort by name/date/size, search, save-to-directory
- **Recent files** — quick access to last 5 opened files
- **Multi-folder scanning** — recursive PDF discovery with Isolate
- **"Open with" support** — native Android intent handler

## Stack

- **Framework:** Flutter 3.x
- **State management:** Provider
- **PDF rendering:** pdfrx (native annotations)
- **Encryption:** AES-256-GCM (encrypt package + pointycastle)
- **Storage:** SharedPreferences, FlutterSecureStorage
- **Biometrics:** local_auth
- **SVG:** flutter_svg
- **CI:** GitHub Actions (analyze + test on push/PR)

## Test coverage

| Layer | Count | What |
|-------|-------|------|
| Unit (small) | 6 files | Encryption, file, tag, settings, highlight, app lock services |
| Integration (medium) | 5 files | AppState, TagProvider, FileOperations, HighlightProvider, BiometricAuth |
| Widget (large) | 5 files | App root, viewer screen states, app lock screen, biometric unlock dialog, smoke tests |

Total: **340 test cases** across 22 files. 3-layer addyosmani pyramid.

`dart analyze` → 0 issues

### Test breakdown by feature

| Feature | Tests | Files |
|---------|-------|-------|
| Highlight | 17 | 1 |
| Biometric Auth | 8 | 1 |
| App Lock | 17 | 1 |
| Core (Phase 1–2) | 223 | 12 |

## Website

The Feya PDF landing page lives in the HERO repo:

- **Source:** `mashalalfas/hero/skills/web-designer/feya-website/index.html`
- **Live:** https://mashalalfas.github.io/FeyaPDF/

## Build

The app embeds the current git commit hash (shown in Settings → About → Commit) at build time via `--dart-define=GIT_HASH`. Use the wrapper so the hash is always injected:

```bash
./tool/build_apk.sh release                 # build a release APK
./tool/build_apk.sh profile --install       # build a profile APK and install it on a connected device
./tool/build_apk.sh debug                   # build a debug APK
```

## CI

GitHub Actions runs on every push/PR:
1. `dart analyze`
2. `flutter test` (fast tests; 1MB encryption round-trip excluded — 50s)

## Learnings

- Army protocol: max 2-3 files per soldier, decompose before spawning
- Don't give full builds to single agents — slice by layer
- RED→GREEN→REFACTOR catches more bugs than post-hoc tests
