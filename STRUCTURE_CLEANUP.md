# FeyaPDF — Structure Cleanup Summary

**Date:** 2026-07-05
**Branch:** master
**Type:** Pure structural refactor (no logic changes)
**Files touched:** 75 (55 lib + 22 test + 2 docs/scripts)

---

## TL;DR

`lib/` was reorganized from a **layer-based** layout (`models/`, `providers/`,
`services/`, `screens/`, `widgets/`) into a **feature-based** + **shared/core**
layout that follows Flutter clean-architecture conventions. Every file was
moved with `git mv` (history preserved), every import was rewritten, and all
340 tests still pass with the same exit code as the pre-refactor baseline.

---

## Before → after

### Before (layer-based, 55 files under `lib/`)

```
lib/
├── main.dart
├── theme.dart
├── models/        (6)   # pdf_file, bookmark, highlight, tag, secure_folder, user_profile
├── providers/     (13)  # app_state, bookmark, encryption, file_operations, ...
├── screens/       (4)   # home, settings, tags, viewer
├── services/      (13)  # file_service, encryption_service, bookmark_service, ...
└── widgets/       (15)  # file_list_tile, tag_chip, secure_folder_card, ...
```

### After (feature-based, 55 files under `lib/`)

```
lib/
├── main.dart
├── theme.dart
├── core/
│   ├── models/    (1)   # pdf_file (used by 4+ features → core)
│   └── utils/     (0)   # reserved
├── features/
│   ├── viewer/         (5) # PDF viewing
│   │   ├── viewer_screen.dart
│   │   ├── page_navigation.dart
│   │   ├── providers/search_provider.dart
│   │   └── widgets/{search_bar, thumbnail_grid}.dart
│   ├── encryption/     (5) # AES-GCM encryption feature
│   │   ├── {encryption_service, encryption_provider, passphrase_strength}.dart
│   │   └── widgets/{passphrase_dialog, encryption_badge}.dart
│   ├── bookmarks/      (4) # bookmarks
│   │   ├── {bookmark, bookmark_service, bookmark_provider}.dart
│   │   └── widgets/bookmarks_panel.dart
│   ├── highlights/     (4) # highlights
│   │   ├── {highlight, highlight_service, highlight_provider}.dart
│   │   └── widgets/highlights_panel.dart
│   ├── tags/           (6) # tags
│   │   ├── {tag, tag_service, tag_provider, tags_screen}.dart
│   │   └── widgets/{tag_chip, tag_picker_dialog}.dart
│   ├── settings/       (6) # settings + backup + profile
│   │   └── {settings_service, settings_provider, settings_screen,
│   │       backup_service, backup_provider, user_profile}.dart
│   ├── file_management/ (12) # file browser, recent files, favorites, etc.
│   │   ├── home_screen.dart
│   │   ├── {file_service, permission_service, intent_handler}.dart
│   │   ├── {app_state, file_operations_provider, recent_files_provider,
│   │   │   favorites_provider, scanned_paths_provider, selection_provider,
│   │   │   sort_search_provider}.dart
│   │   └── widgets/file_list_tile.dart
│   └── security/       (9) # app lock, biometrics, secure folder
│       ├── {secure_folder, app_lock_service, biometric_auth_service,
│       │   secure_folder_service, secure_folder_provider}.dart
│       └── widgets/{app_lock_screen, biometric_unlock_dialog,
│                      secure_folder_card, secure_folder_import_dialog}.dart
└── shared/
    └── widgets/  (1)     # lottie_route (reserved for true cross-feature widgets)
```

### File count reconciliation

| Bucket | Before | After |
| --- | ---: | ---: |
| `lib/` total | 55 | 55 |
| Root `lib/` (`main.dart`, `theme.dart`) | 2 | 2 |
| `models/` (was) | 6 | — |
| `providers/` (was) | 13 | — |
| `screens/` (was) | 4 | — |
| `services/` (was) | 13 | — |
| `widgets/` (was) | 15 | — |
| `core/models/` | — | 1 |
| `features/viewer/` | — | 5 |
| `features/encryption/` | — | 5 |
| `features/bookmarks/` | — | 4 |
| `features/highlights/` | — | 4 |
| `features/tags/` | — | 6 |
| `features/settings/` | — | 6 |
| `features/file_management/` | — | 12 |
| `features/security/` | — | 9 |
| `shared/widgets/` | — | 1 |

**No files were created or deleted.** Every one of the 55 `.dart` files in
`lib/` was relocated; `lib/widgets/lottie_route.dart` and
`lib/models/secure_folder.dart` were preserved per the brief's "do not delete"
rule, even though no other file in the repo currently imports them.

---

## What needed updating

### `lib/` (147 import lines rewritten)

Originally every cross-directory reference was a relative path
(`'../providers/app_state.dart'`, `'../models/pdf_file.dart'`,
`'../services/bookmark_service.dart'`, etc.). After the move those relative
paths would all be incorrect.

**Decision:** convert every relative import inside `lib/` to a package import
(`package:feya_pdf/features/...`). Two reasons:

1. **Unambiguous single source of truth** — every import string maps to a
   unique target regardless of the caller's depth.
2. **Style-consistent with the existing test suite** — `test/` already uses
   `package:feya_pdf/...`, so this brings `lib/` into the same style.

Same-directory siblings (e.g. `import 'tag_chip.dart';` in
`features/tags/widgets/tag_picker_dialog.dart`) were preserved as bare names.

### `test/` (75 import lines rewritten)

Each test file used `package:feya_pdf/<old-path>` and each was rewritten to
`package:feya_pdf/<new-path>`. Only the post-`feya_pdf/` path fragment changed;
test file structure, file content, and test counts are **identical**.

The migration was deterministic: a single Python script
(`scripts/migrate_imports.py`) holds the old-path → new-path table, parses
every `import '...';` line in `lib/` and every `package:feya_pdf/...` line in
`test/`, and rewrites them in place. The script also:

* Skips `dart:` and third-party `package:` imports.
* Refuses to resolve bare-name imports via the filesystem unless the target
  actually exists (this catches typos before they show up at analyze-time).
* Is idempotent — running it twice produces no diff after the first run.

---

## Verification

### `flutter analyze`

| State | Errors | Warnings | Infos |
| --- | ---: | ---: | ---: |
| Before refactor (baseline) | 0 | 0 | 2 (pre-existing) |
| After refactor | 0 | 0 | 2 (same 2 as baseline) |

The 2 info-level lints flagged by the analyzer are
`use_build_context_synchronously` on `home_screen.dart:160` and
`backup_provider.dart:157`. **Verified to predate the refactor** by reverting
to git HEAD and re-running — same 2 lines are flagged at the same content.
They are info-level only and did not block `flutter analyze` returning clean.

### `flutter test`

```
00:00 +1: …
…
02:25 +340 ~4: All tests passed!
```

* 340 tests pass — **identical** to the baseline count.
* Zero skipped, zero failed, zero compilation errors.
* Total runtime ~2:25 — within ±20s of baseline (CPU-load dependent).

---

## Notable design choices

1. **`pdf_file.dart` moved to `core/models/`** — it's imported by 4+ features
   (file_management, security, encryption, viewer) so it doesn't own a
   single feature. Placing it in `core/models/` matches clean-arch norms.

2. **`shared/widgets/lottie_route.dart`** — `LottieRoute` is not currently
   imported by anything in `lib/` or `test/`, but the brief says "do not
   delete". Moved to `shared/widgets/` as the catch-all for genuine
   cross-feature UI primitives; can be used later as new features land.

3. **`models/secure_folder.dart`** — `SecureFolder` class is never imported
   either. Moved into `features/security/secure_folder.dart` because it's a
   security-domain concept.

4. **`page_navigation.dart`** — only `test/page_navigation_test.dart` imports
   it. It's a viewer-navigation helper, so it lives in `features/viewer/`.

5. **`backup_*` grouped under `settings/`** — even though it serialises models
   from 4 features, it's user-driven from the Settings screen and the
   dependency direction is natural (`settings` → every other feature's model).

6. **`intention_handler.dart` under `file_management/`** — it handles
   Android intents for opening PDFs, which is squarely the file-browser
   concern.

7. **`tag_picker_dialog` and `tag_chip` widgets live under `tags/widgets/`** —
   `home_screen.dart` and `file_list_tile.dart` import them cross-feature,
   which is the natural cost of having a tag-system that ornaments file
   listings.

8. **`secure_folder_card` imports `viewer_screen`** — once moved to
   `features/security/widgets/`, that import had to traverse one extra
   directory hop (`'../screens/viewer_screen.dart'` → `package:feya_pdf/features/viewer/viewer_screen.dart`).
   This is fine; the alternative — sharing `viewer_screen` via `shared/` —
   would force a smaller-scoped widget into a bag of generic utilities.

---

## Files added (docs / tooling, not source)

| File | Purpose |
| --- | --- |
| `PLAN.md` | The pre-execution plan with the full dependency map |
| `STRUCTURE_CLEANUP.md` | This document |
| `scripts/migrate_imports.py` | Re-runnable, idempotent import-rewriter |

No source files (`.dart`) were added. No source files were deleted. The repo
state changes only paths and import strings.

---

## Git state

```
$ git status --short | wc -l       # lines of git status output
55 + 22 + tooling = 80

$ git diff --stat HEAD -- lib/ test/ | tail -1
75 files changed, 262 insertions(+), 210 deletions(-)
```

`git log --follow` continues to work on every moved file — e.g.
`git log --follow lib/core/models/pdf_file.dart` shows the full pre-move
history of `lib/models/pdf_file.dart`.

---

## How to review

```bash
cd ~/Development/FeyaPDF

# 1. View the plan that was executed
cat PLAN.md

# 2. Run the verification commands
flutter analyze    # → 2 info (pre-existing, non-blocking)
flutter test       # → +340 -0 ~4 All tests passed!

# 3. See exactly which imports changed
git diff HEAD -- lib/ test/ | head -200

# 4. Confirm history was preserved on a sample file
git log --follow --oneline lib/core/models/pdf_file.dart | head
```
