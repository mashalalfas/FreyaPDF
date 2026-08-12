# Changelog

All notable changes to Freya PDF are documented here. Version format follows
`pubspec.yaml` (`1.2.0+6` = version 1.2.0, build 6).

## [1.3.5+12] — 2026-08-12

### Added

- **Page-turn swipe mode** — horizontal page-turn reading mode with snap-to-page, toggled via settings. Uses pdfrx `layoutPages` for horizontal layout; single-finger swipes >25% page width trigger page navigation.
- Rotate-to-fill width on orientation change.
- Fullscreen topbar collapse.

### Fixed

- **Biometric prompt** — switched `MainActivity` to `FlutterFragmentActivity` so `local_auth` renders the biometric prompt correctly.
- **Highlight draw repaint** — force viewer `invalidate()` after draw so committed highlight boxes appear immediately without manual interaction.
- **Zoom controls** — removed auto-fade (was causing "zoom button disappeared" feedback); controls now stay visible.
- Swipe-mode snap no longer fires on pinch-zoom `onInteractionEnd` — gated on `pointerCount == 1` and displacement threshold.
- Rotation refit in page-turn mode (was missing `onViewSizeChanged` handler → page off-center after rotate).

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
