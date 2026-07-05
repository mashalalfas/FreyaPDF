# FeyaPDF — Structure Cleanup Plan

## Goal
Reorganize `lib/` from layer-based (models/providers/services/widgets/screens)
to feature-based + shared/core layout following Flutter clean-architecture best
practices. Preserve **every** file, **every** test, and **all** git history.

## Dependency map (verified via `grep` over lib/ + test/)

Cross-feature imports observed:

| From feature | Imports from other features |
| --- | --- |
| `settings/backup_service` | `tags/tag`, `highlights/highlight`, `bookmarks/bookmark`, `settings/user_profile` |
| `viewer/viewer_screen` | `highlights/{provider,model,panel}`, `bookmarks/{provider,model,panel}`, `security/biometric_unlock_dialog`, `encryption/{provider}`, `file_management/{provider,model}`, `core/pdf_file` |
| `file_management/home_screen` | `tags/{provider,chip,picker_dialog,model}`, `bookmarks/provider`, `encryption/{provider,passphrase_dialog,badge}`, `settings/provider`, `viewer/{screen}`, `security/{secure_folder_card}` |
| `security/secure_folder_card` | `encryption/passphrase_dialog`, `file_management/{provider,model,file_list_tile}`, `viewer/screen` |
| `tags/*` | none cross-feature |
| `highlights/*` | none cross-feature |
| `bookmarks/*` | none cross-feature |
| `encryption/*` | `core/pdf_file` (file_operations_provider pulls both) |

Decision: cross-feature dependency on **viewer → highlights/bookmarks/security**
is natural; **settings → tags/highlights/bookmarks** is needed for backup and
acceptable.

## Target layout

```
lib/
├── main.dart                                 (root, unchanged)
├── theme.dart                                (root, unchanged)
├── core/
│   ├── models/
│   │   └── pdf_file.dart                     (used by ≥4 features)
│   └── utils/                                (empty for now — reserved)
├── features/
│   ├── viewer/
│   │   ├── viewer_screen.dart
│   │   ├── page_navigation.dart
│   │   └── providers/
│   │       └── search_provider.dart
│   │   └── widgets/
│   │       ├── search_bar.dart
│   │       └── thumbnail_grid.dart
│   ├── encryption/
│   │   ├── encryption_service.dart
│   │   ├── encryption_provider.dart
│   │   ├── passphrase_strength.dart
│   │   └── widgets/
│   │       ├── passphrase_dialog.dart
│   │       └── encryption_badge.dart
│   ├── bookmarks/
│   │   ├── bookmark.dart                     (model + extension kept as class Bookmark)
│   │   ├── bookmark_service.dart
│   │   ├── bookmark_provider.dart
│   │   └── widgets/
│   │       └── bookmarks_panel.dart
│   ├── highlights/
│   │   ├── highlight.dart
│   │   ├── highlight_service.dart
│   │   ├── highlight_provider.dart
│   │   └── widgets/
│   │       └── highlights_panel.dart
│   ├── tags/
│   │   ├── tag.dart
│   │   ├── tag_service.dart
│   │   ├── tag_provider.dart
│   │   ├── tags_screen.dart
│   │   └── widgets/
│   │       ├── tag_chip.dart
│   │       └── tag_picker_dialog.dart
│   ├── settings/
│   │   ├── user_profile.dart
│   │   ├── settings_service.dart
│   │   ├── settings_provider.dart
│   │   ├── backup_service.dart
│   │   ├── backup_provider.dart
│   │   └── settings_screen.dart
│   ├── file_management/
│   │   ├── home_screen.dart
│   │   ├── intent_handler.dart
│   │   ├── file_service.dart
│   │   ├── permission_service.dart
│   │   ├── app_state.dart
│   │   ├── file_operations_provider.dart
│   │   ├── recent_files_provider.dart
│   │   ├── favorites_provider.dart
│   │   ├── scanned_paths_provider.dart
│   │   ├── selection_provider.dart
│   │   ├── sort_search_provider.dart
│   │   └── widgets/
│   │       └── file_list_tile.dart
│   └── security/
│       ├── secure_folder.dart                (model; dead code preserved per rules)
│       ├── app_lock_service.dart
│       ├── biometric_auth_service.dart
│       ├── secure_folder_service.dart
│       ├── secure_folder_provider.dart
│       └── widgets/
│           ├── app_lock_screen.dart
│           ├── biometric_unlock_dialog.dart
│           ├── secure_folder_card.dart
│           └── secure_folder_import_dialog.dart
└── shared/
    └── widgets/
        └── lottie_route.dart                 (dead code; preserved per rules)
```

## Notes

* `lib/widgets/lottie_route.dart` and `lib/models/secure_folder.dart` have **no
  importers** anywhere in `lib/` or `test/`. The brief says "do NOT delete", so
  they are moved to `shared/widgets/` and `features/security/` respectively.
* `lib/services/page_navigation.dart` is only imported from `test/page_navigation_test.dart`.
  It belongs with the viewer feature (it's a navigation helper for the viewer);
  moved to `features/viewer/page_navigation.dart`.
* `models/pdf_file.dart` is used by 4+ features → `core/models/`.
* No logic changes; the only edits will be import paths.
* All file moves use `git mv` so the git history is preserved.

## Execution order

1. Create all target directories.
2. `git mv` all 55 files in feature batches.
3. Patch imports in every moved file in `lib/`.
4. Patch imports in every test file in `test/`.
5. `flutter analyze` (target: 0 issues; pre-baseline preserved).
6. `flutter test` (target: all tests pass).
7. Write `STRUCTURE_CLEANUP.md`.

## Risk mitigation

* After each feature batch, run a quick `grep` to spot any leftover
  `providers/...` or `services/...` style import that should now live under the
  new path.
* Done before committing — once everything's clean, commit on the existing
  master branch as a single focused refactor (per AGENTS.md style of grouping
  related changes).
