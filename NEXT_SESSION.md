# NEXT SESSION — FreyaPDF

**State: v1.8.0+22 SHIPPED (Phase C complete, tag v1.8.0, APK on Drive) → next: Mashal's 1.8.0 eyeball + fixes, then open items**

## Current status

- **v1.8.0+22 released** — master @ `496d6ce` (`chore(release): bump version to 1.8.0+22`), tag **`v1.8.0`** pushed to GitHub
- **Phase C fully merged + pushed** (5 commits: `f5ed52a` foundation → `3857b9a` viewer → `3ef549d` empty states → `507d4e3` FAB file manager → `6cbe161` Save-to-folder visible)
- Tests: **532 passed / 4 skipped / 0 failed**, `flutter analyze` clean
- **Release APK on Drive:** `sook-gdrive:FeyaPDF/FreyaPDF-v1.8.0.apk` (79.4 MB, hash `d37ddc78624d6f95d9d2ddcc29a38fa0` — matches local `build/app/outputs/flutter-apk/app-release.apk`)
- **AWAITING MASHAL'S EYEBALL** of the 1.8.0 APK — his feedback drives the next move
- Repo tidied: all `hero/*` branches deleted, worktrees removed, only `master` + `gh-pages` remain

## What's in v1.8.0 (Phase C)

1. **Viewer toolbar 11 → 4 primary buttons** — TOC · Search · Bookmark · More (rest in overflow: Thumbnails, Dark reading, Highlight, Highlights panel, Share, Fullscreen). Unified across portrait/landscape, no duplicated actions.
2. **Save to folder = primary toolbar button** (Mashal's correction, 2026-08-16: "it's our key selling point") — moved out of More overflow into the always-visible bar (`Icons.save_rounded`, before More).
3. **FAB speed-dial file manager** — `+` expands up → 📄 File | 📁 Folder. File = native SAF multi-select PDFs imported **individually** into library (copied into app storage). Folder = existing bulk scan. Staggered animation + light haptics, ModalBarrier dismiss. **Council guards all implemented:** SHA-256 hash dedupe (1MB+size, "Already in library" toast, never `file(1).pdf`), atomic `.tmp`→rename writes, cumulative-size preview + quota check, inline progress for 5+ files, summary snackbar ("7 imported, 1 failed: x.pdf"), Undo ~5s, no auto-open, highlight-new-files, SAF-only (no MANAGE_EXTERNAL_STORAGE), full-buffer reads for streaming Drive URIs, visible labels + ≥48dp targets, local failure logging.
4. **Empty states with custom Lottie** — shared `EmptyState` widget + hand-authored Lottie (floating document motif, warm tones), replacing all plain text/icon empties (library, search, bookmarks, tags, recent).
5. **AnimatedTheme** — 200ms dark/light crossfade.
6. **Page indicator** — themed surface (`surfaceContainerLow` + `outlineVariant`) instead of raw Container.
7. **Encryption badge** — moved from `Positioned` overlay into tile trailing column.
8. **Snackbar helper** — `FreyaSnackBar.show()` app-wide (43 call sites converted), rounded 12, warm surface, teal accent.

New files: `lib/core/widgets/fab_speed_dial.dart`, `lib/core/widgets/freya_snack_bar.dart`, `lib/features/file_management/pdf_import_service.dart`, `lib/core/widgets/empty_state.dart`, Lottie assets.

## What's next

1. **Mashal's 1.8.0 eyeball** — feedback → route fixes. Test path: open PDF → toolbar (Save to folder!) → FAB File/Folder import from different sources (Downloads/Drive/WhatsApp) → dedupe + Undo → empty states → theme toggle.
2. **Phase D — verification & polish** — analyze + full suite + release build per design plan; device feel-pass.
3. **Skyline install** of 1.8.0 once eyeball passes.

## Open items (still pending)

1. **Coordinated dependency trio** (F-005 remainder): pointycastle 4.x + flutter_secure_storage 11.x + share_plus bump **together** — blocked by encrypt 5.0.3's `^3.6.2` pin and share_plus's win32 `^5.5.3` conflict. One coordinated release.
2. **Tablet no-fingerprint grey-out test** — pending. ⚠️ Serial `HH0001ZRM0481600928` is the HMD **Skyline**, NOT the no-fingerprint tablet. Get the tablet's serial when plugged.
3. **Optional SBOM NOASSERTION resolution** — before any store submission.
4. **8GB swap OOM note** — large builds can OOM on this machine; watch swap / gradle daemon.
5. **Store submission** — Play release readiness (SBOM first, then listing assets, screenshots, privacy policy).
6. **Deferred by design:** third "Browse" option in FAB speed-dial (in-app file browser) — only if Mashal ever wants it.

## Constraints / Rules

- **Army roster:** `/home/max/.hero/army.yaml`. No stepfun/xiaomi lanes (stopped 2026-08-11). **Escalation: T1→T2 GLM 5.2 (byteplus-plan/ark-code-latest, ARK coding plan) · T2→T3 nuclear Qwen 3.8 Max (bailian-token-plan/qwen3.8-max, 983K ctx)** — corrected 2026-08-15. Bailian Token Plan: qwen3.8-max, qwen3.7-max/plus, qwen3.6-flash, glm-5.2, deepseek-v4-pro variants.
- **Hero release command exists** — prefer it over manual steps (`hero release --sandbox FreyaPDF --minor --tag` worked for 1.8.0).
- Go quiet and execute; don't ask for confirmation when the task is already authorized.
- Test lifecycle state sequences + convenience features must never bypass the auth boundary (lesson from v1.5.1 relock / passphrase regressions).
- rclone quirk learned 2026-08-16: `rclone copy <file> "remote:dir/name.apk"` treats the dest as a **directory** — upload to the folder, then `rclone moveto` to rename. Always hash-verify after upload.

---

## 🚀 Ready-to-Paste Pickup Prompt

```
Resume FreyaPDF (v1.8.0+22 SHIPPED — Phase C complete, tag v1.8.0 pushed, APK on Drive as FreyaPDF-v1.8.0.apk, awaiting Mashal's eyeball).

Full context: NEXT_SESSION.md in the repo root + docs/DESIGN_IMPROVEMENT_PLAN.md.

STEP 1 — Wait for Mashal's verdict on the 1.8.0 APK (toolbar 4+Save-to-folder, FAB speed-dial File/Folder import, Lottie empty states, AnimatedTheme). Route any feedback fixes via soldiers, verify (analyze clean + 532/4/0), commit, hero release (patch bump), push, re-upload to Drive.

STEP 2 — After eyeball passes: install 1.8.0 on Skyline, mark Phase C closed, then pick up in priority order:
1. Coordinated dep trio (pointycastle 4.x + flutter_secure_storage 11.x + share_plus together — blocked by encrypt ^3.6.2 + win32 ^5.5.3; one coordinated release)
2. Tablet no-fingerprint grey-out test (get the tablet's serial — Skyline is HH0001ZRM0481600928, NOT the tablet)
3. SBOM NOASSERTION cleanup (before store submission)
4. Phase D verification/polish per DESIGN_IMPROVEMENT_PLAN.md
5. Store submission readiness (listing, screenshots, privacy policy)

Keep visible: 8GB swap/OOM note (watch gradle daemon). Deferred: FAB "Browse" third option (only if Mashal wants an in-app browser).
```
