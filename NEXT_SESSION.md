# NEXT SESSION — FreyaPDF

**State: v1.7.0+21 Phase B SHIPPED (merged + pushed), font fix verified → next: Phase C (design character + FAB file manager)**

## Current status

- **Phase B merged to master + pushed to GitHub** — `843fdc8` (`fix(theme): apply Fraunces serif to actually-used text roles`) on top of `6e8fb23` (`feat(design): Phase B font personality`)
- Font fix **verified by Mashal** (2026-08-15): Fraunces now renders on app name, file names, reader title — all visible text
- Version: **1.7.0+21** · Tests: 532 passed / 4 skipped / 0 failed · `flutter analyze` clean
- Fixed APK on Drive: `sook-gdrive:FeyaPDF/FreyaPDF-v1.7.0.apk` (hash `7d6b706e…` matches local, only copy in folder — old broken duplicate deleted)

## What's in Phase B (master)

1. **Font personality — anti-generic-AI layer:** Fraunces display serif + Inter body pairing (full 13-role Material 3 TextTheme in `lib/theme.dart`).
2. **~84 inline fontSize refs swept to theme roles** across ~16 widget files — 0 references remain outside `theme.dart`.
3. **Font-wiring fix (843fdc8):** serif moved from unused roles (`display*`/`headlineLarge/Medium` — 0 usages) to the roles the app actually renders: `titleLarge`, `titleMedium`, `headlineSmall` + `appBarTheme.titleTextStyle` (light+dark). Body/labels stay Inter for readability.
4. **pubspec version** 1.6.1+20 → 1.7.0+21.
5. **test/encryption_service_test.dart timeout fix** — 30s → 60s on the slow 4MB crypto round-trip test.
6. **assets/fonts/Fraunces[wght].ttf** added.

## Approved roadmap (per docs/DESIGN_IMPROVEMENT_PLAN.md)

- **Phase A** — ✅ shipped (consistency foundation).
- **Phase B** — ✅ SHIPPED + pushed (font personality, above).
- **Phase C (NEXT):** viewer toolbar 11→4 buttons, empty states with custom Lottie, AnimatedTheme, selection AppBar continuity, page indicator, encryption badge, snackbar helper. **+ NEW: FAB speed-dial file manager** (Mashal-approved 2026-08-15 — see below).
- **Phase D:** (per plan doc — see docs/DESIGN_IMPROVEMENT_PLAN.md for details).

### 🆕 FAB speed-dial file manager (added to Phase C, approved 2026-08-15)

**Decision (Mashal):** FAB expands vertically with **File** / **Folder** options instead of a separate file-manager screen.

- Tap FAB → expands up: 📄 **File** | 📁 **Folder**
- **File** → native SAF system picker (multi-select PDFs) → each file imported **individually** into the library (copied into app storage so it survives the original moving/deleting)
- **Folder** → existing `_pickDirectory()` bulk-scan flow, untouched
- Expansion uses Freya's tactile details: staggered animation + light haptics (existing patterns)
- **No custom in-app file browser** — native SAF picker is the file finder (search/recents/sorted for free, small permission surface). If a real in-app browser is ever wanted, add a third "Browse" option to the dial.
- Scope: ~½ soldier day extra on Phase C.

## Open items

1. **Install APK on Skyline** — `FreyaPDF-v1.7.0.apk` from Drive; Phase B feel-test done on another phone already (✅ Fraunces verified).
2. **DESIGN PHASE C** — toolbar, empty states Lottie, AnimatedTheme, AppBar continuity, page indicator, encryption badge, snackbar helper **+ FAB speed-dial file manager** (above). Bump → 1.8.0+22.
3. **Coordinated dependency trio** (F-005 remainder): pointycastle 4.x + flutter_secure_storage 11.x + share_plus bump **together** — blocked by encrypt 5.0.3's `^3.6.2` pin and share_plus's win32 `^5.5.3` conflict. Schedule one coordinated release.
4. **Tablet no-fingerprint grey-out test** — still pending. ⚠️ Confirm serial: HH0001ZRM0481600928 is the HMD **Skyline**, NOT the no-fingerprint tablet. Different device; get its serial when plugged.
5. **Optional SBOM NOASSERTION resolution** — before any store submission.
6. **8GB swap OOM note** — large builds can hit OOM on this machine; watch swap / gradle daemon.

## Constraints / Rules

- **Army roster:** `/home/max/.hero/army.yaml`. no stepfun / xiaomi lanes — all stepfun & xiaomi (MiMo) lanes stopped 2026-08-11 per Mashal. Bailian Token Plan added 2026-08-14 (`bailian-token-plan`): qwen3.8-max (983K ctx reasoning) etc. Available. (Session used deepseek-v4-flash per Mashal.)
- **Hero release command exists** — prefer it over manual steps for shipping.
- Go quiet and execute; don't ask for confirmation when the task is already authorized.
- Test lifecycle state sequences + convenience features must never bypass the auth boundary (lesson from v1.5.1 relock / passphrase regressions).

---

## 🚀 Ready-to-Paste Pickup Prompt

```
Resume FreyaPDF (v1.7.0+21 Phase B SHIPPED — merged 843fdc8 + pushed, font fix verified, APK on Drive).

Full context: NEXT_SESSION.md in the repo root + docs/DESIGN_IMPROVEMENT_PLAN.md.

Pick up DESIGN PHASE C (per docs/DESIGN_IMPROVEMENT_PLAN.md):
1. Viewer toolbar 11 → 4 buttons (declutter; keep the essential actions, move rest to overflow/secondary surface)
2. Empty states with custom Lottie animations (replace plain text/icon empties)
3. AnimatedTheme (smooth dark/light transitions)
4. Selection-mode AppBar continuity (no flicker when entering/exiting selection)
5. Page indicator (current/total in viewer)
6. Encryption badge (visible encrypted-state indicator)
7. Snackbar helper (consistent themed snackbars app-wide)
8. FAB speed-dial file manager (Mashal-approved): FAB expands vertically → "File" (native SAF multi-select PDFs, import each individually into library, copy into app storage) | "Folder" (existing bulk scan). Staggered animation + light haptics. NO custom file-browser screen.
Keep 532 tests passing + flutter analyze clean. Bump version 1.7.0+21 → 1.8.0+22. Ship via hero release after Mashal's eyeball.

Open items to keep visible: coordinated dep trio (pointycastle 4.x + FSS 11.x + share_plus — blocked by encrypt ^3.6.2 + win32 ^5.5.3), tablet no-fingerprint grey-out test (confirm serial — Skyline is HH0001ZRM0481600928, NOT the tablet), optional SBOM NOASSERTION, 8GB swap/OOM note.
```
