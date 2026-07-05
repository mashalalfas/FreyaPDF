# FeyaPDF — TODO

> Generated: 2026-07-05 | From 3-soldier mission (score 6.4/10 B Tier)

## 🔴 P0 — Ship Blockers

- [ ] **Biometric passphrase stored in plain SharedPreferences** — defeats encryption on rooted devices. Move to `flutter_secure_storage`.
- [ ] **Backups are plain-text JSON** — bookmarks, highlights, tags, file paths all recoverable without decryption. Encrypt backup exports.

## 🟠 P1 — Viewer UI Bugs

- [ ] **TOC panel back button overlap** — Bottom sheet panels (TOC, bookmarks, highlights) have custom close/back icons that overlap with Android's native back gesture. Remove redundant back icons — Android back button/gesture already dismisses bottom sheets.
- [ ] **Table of Contents not generating** — `_loadOutline()` in `viewer_screen.dart` calls `document.loadOutline()` but TOC data may be empty or failing silently. Investigate why outline isn't extracted from PDFs that have TOC metadata.
- [ ] **Thumbnail center-strip rendering** — Thumbnails in grid show only center 1/3 of page. Root cause: `_renderPage()` renders at `_renderWidth = 160` with natural page aspect ratio, but grid cell is sized for A4 default. `BoxFit.contain` inside `AspectRatio` widget causes blank sides on non-A4 pages. Need to match thumbnail render dimensions to actual grid cell dimensions.

---

_Add your points below ↓_
