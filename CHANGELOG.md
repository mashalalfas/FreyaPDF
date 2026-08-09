# Changelog

All notable changes to Freya PDF are documented here. Version format follows
`pubspec.yaml` (`1.2.0+6` = version 1.2.0, build 6).

## [1.2.0+6] — 2026-08-09

### Fixed

- **PDF search ANR** — toggling search no longer freezes the app. Root cause:
  `SearchBarWidget` attached the same `FocusNode` twice (outer `Focus` +
  `TextField`'s internal `EditableText`), corrupting Flutter's focus tree and
  producing `Input dispatching timed out (FocusEvent)` ANRs. The search bar now
  opens instantly and returns results.
- Added `RepaintBoundary` around the PDF viewer and search overlay, and removed
  the overlay `AnimatedSwitcher`, to isolate pdfrx repaints.
- Search hardening: no full-document page loading, per-page text caps, single-page
  match geometry, and gates for very large / image-only documents.

### Added

- Secure "remember PDF password" flow (`PdfPasswordStorage`, prompt dialog,
  viewer wiring) with per-file secure storage.
- Build wrapper `tool/build_apk.sh` that embeds the current git commit hash
  (shown in **Settings → About → Commit**).
- Consolidated documentation under `docs/clean/`.

### Changed

- Version bumped to `1.2.0` (build `6`).

## [1.1.3+5] — prior

- Bundled the Inter font locally (removed runtime `google_fonts` fetch).
- Restored folder permission flow; FAB changed to `+` icon.
- SAF-based file access for Android 10+ (no `MANAGE_EXTERNAL_STORAGE`).
- Release signing wired via `key.properties`.
- Pre-launch hardening: security, legal, ProGuard, storage migration.
- Git commit hash shown in settings; branding added to splash and About.
- Auto-update system via GitHub Releases; new app icon.
- Rectangle highlight coordinate fixes; crash guard; logo asset.
