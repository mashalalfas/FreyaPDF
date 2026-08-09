# Plan 002: Decompose AppState god provider

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise.
>
> **Drift check**: `git diff --stat abe2b97..HEAD -- lib/providers/app_state.dart lib/providers/`
> If app_state.dart changed since planned-at SHA, compare code excerpts
> against live code; on mismatch, STOP and report.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (touches all callers; must preserve behavior)
- **Depends on**: none (but test coverage from 001 helps)
- **Category**: tech-debt
- **Planned at**: commit `abe2b97`, 2026-06-13

## Why this matters

`AppState` (512 lines) handles: directory loading, file caching, sorting, search, file selection, encryption orchestration, file sharing, recent files persistence, multi-folder scanning, and `saveToLocal()`. This violates single-responsibility, makes testing hard, and every new feature requires modifying the same megafile. Splitting it into focused providers makes each piece testable, composable, and independently maintainable.

## Current state

Current `AppState` responsibilities (all in one file `lib/providers/app_state.dart`):

1. **File browsing** — `loadDirectory()`, `refresh()`, file cache, `_files`, `_currentDir`
2. **Sorting** — `SortBy`/`SortOrder` enum, `sortBy`/`sortOrder` getters/setters, sort logic in `files` getter
3. **Search** — `_searchQuery`, `setSearchQuery()`, search filter in `files` getter
4. **File selection** — `selectFile()`, `closeFile()`, `_selectedFile`
5. **Encryption orchestration** — `encryptFile()`, `autoEncryptFile()`, `decryptForViewing()`, `getPdfBytes()`
6. **Sharing** — `shareFile()` (handles encrypted files)
7. **Recent files** — `_recentFiles`, `loadRecentFiles()`, `_addToRecent()`, `_saveRecentFiles()`
8. **Persistence** — `savePersistedDir()`, `loadPersistedDir()`, `persistAfterPick()`, scanned paths
9. **Multi-folder scanning** — `loadAllDirectories()`, `_scannedPaths`
10. **Save to local** — `saveToLocal()`
11. **File operations** — `deleteFile()` (with cache invalidation)

Callers (files that import app_state.dart):
- `lib/main.dart` — attaches providers
- `lib/screens/home_screen.dart` — watches AppState for file list, sort, search, triggers encrypt/share/delete
- `lib/screens/viewer_screen.dart` — reads decrypted bytes via `getPdfBytes()`, calls `saveToLocal()`

Conventions to match:
- Provider pattern via `ChangeNotifier` + `notifyListeners()`
- Files organized as `lib/providers/<name>_provider.dart`
- Import style: `'package:feya_pdf/providers/<name>.dart'`

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Analyze | `dart analyze` | No issues found |
| Tests | `flutter test` | All pass |

## Scope

**In scope**:
- `lib/providers/app_state.dart` — strip to core file-browsing + selection + cache only (move rest out)
- Create `lib/providers/file_operations_provider.dart` — delete, save-to-local, share, encryption orchestration
- Create `lib/providers/recent_files_provider.dart` — recent files + persistence
- Create `lib/providers/scanned_paths_provider.dart` — scanned paths + multi-directory loading
- `lib/providers/sort_search_provider.dart` — sort and search state

**Out of scope**:
- Do NOT change model files (`lib/models/`)
- Do NOT change service files (`lib/services/`)
- Do NOT change screen/widget files beyond import/constructor updates
- Do NOT add test files (handled by Plan 001)

## Steps

### Step 1: Create `lib/providers/sort_search_provider.dart`

Extract sort and search state from AppState:

```dart
import 'package:flutter/material.dart';
import '../models/pdf_file.dart';

enum SortBy { name, modified, size }
enum SortOrder { asc, desc }

class SortSearchProvider extends ChangeNotifier {
  SortBy _sortBy = SortBy.modified;
  SortOrder _sortOrder = SortOrder.desc;
  String _searchQuery = '';

  SortBy get sortBy => _sortBy;
  SortOrder get sortOrder => _sortOrder;
  String get searchQuery => _searchQuery;

  set sortBy(SortBy value) { _sortBy = value; notifyListeners(); }
  set sortOrder(SortOrder value) { _sortOrder = value; notifyListeners(); }
  void setSearchQuery(String query) { _searchQuery = query; notifyListeners(); }

  List<PdfFile> apply(List<PdfFile> files) {
    var sorted = List<PdfFile>.from(files);
    sorted.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case SortBy.name: cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortBy.modified: cmp = a.modified.compareTo(b.modified);
        case SortBy.size: cmp = a.sizeBytes.compareTo(b.sizeBytes);
      }
      return _sortOrder == SortOrder.asc ? cmp : -cmp;
    });
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      sorted = sorted.where((f) => f.name.toLowerCase().contains(q)).toList();
    }
    return sorted;
  }
}
```

**Verify**: `dart analyze` → 0 issues

### Step 2: Create `lib/providers/file_operations_provider.dart`

Extract encryption, sharing, save-to-local, and delete from AppState:

- Depends on `EncryptionProvider` and `SettingsProvider` (use `attachEncryption`/`attachSettings` pattern from existing codebase)
- Move: `deleteFile()`, `encryptFile()`, `autoEncryptFile()`, `decryptForViewing()`, `getPdfBytes()`, `shareFile()`, `saveToLocal()`
- Also move `SaveResult` enum and `readPdfBytes()`
- Takes a reference to `AppState` or receives file lists via method parameters

**Verify**: `dart analyze` → 0 issues

### Step 3: Create `lib/providers/recent_files_provider.dart`

Extract recent files logic:

- Move: `_recentFiles`, `loadRecentFiles()`, `_saveRecentFiles()`, `_addToRecent()`, `recentFilePaths`, `recentFilesInDir` (including cache logic)

**Verify**: `dart analyze` → 0 issues

### Step 4: Create `lib/providers/scanned_paths_provider.dart`

Extract scanned paths and multi-directory loading:

- Move: `_scannedPaths`, `loadScannedPaths()`, `addScannedPath()`, `saveScannedPaths()`, `loadAllDirectories()`, `getSourceDirName()`
- Keep basic `persistAfterPick()` route

**Verify**: `dart analyze` → 0 issues

### Step 5: Strip AppState to core

Remove moved code from `app_state.dart`. Keep only:
- `_files`, `_currentDir`, `_isLoading`, `_error`
- `loadDirectory()`, `refresh()`, `_fileCache`
- `files` getter (delegate sorting/search to SortSearchProvider via method parameter or injected reference)
- `allFiles`, `isLoading`, `error`, `hasFiles`, `currentDir`, `dirName`

**Verify**: `dart analyze` → 0 issues (expected — callers not updated yet will have errors)

### Step 6: Update `lib/main.dart`

Register new providers in MultiProvider:
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => EncryptionProvider()),
    ChangeNotifierProvider(create: (_) => SecureFolderProvider()),
    ChangeNotifierProvider(create: (_) => SettingsProvider(settingsService)),
    ChangeNotifierProvider(create: (_) => TagProvider(tagService)),
    ChangeNotifierProvider(create: (_) => SortSearchProvider()),
    ChangeNotifierProvider(create: (_) => RecentFilesProvider()),
    ChangeNotifierProvider(create: (_) => ScannedPathsProvider()),
    ChangeNotifierProvider(create: (_) => AppState()),
    ChangeNotifierProvider(create: (_) => FileOperationsProvider()),
  ],
  ...
)
```
Update `attach*` wiring accordingly — each provider now initializes independently.

**Verify**: `dart analyze` → 0 issues

### Step 7: Update `lib/screens/home_screen.dart`

Replace all `context.read<AppState>()` calls for sort/search with `context.read<SortSearchProvider>()`.
Replace encrypt/share/delete calls with `context.read<FileOperationsProvider>()`.
Replace recent file access with `context.read<RecentFilesProvider>()`.
Keep directory loading/selection on `AppState`.

**Verify**: `dart analyze` → 0 issues

### Step 8: Update `lib/screens/viewer_screen.dart`

Replace `getPdfBytes()` and `saveToLocal()` calls with `context.read<FileOperationsProvider>()`.

**Verify**: `dart analyze` → 0 issues

### Step 9: Final verification

```bash
flutter analyze
flutter test
```
Both must pass with 0 issues.

## Done criteria

- [ ] `dart analyze` exits 0
- [ ] `flutter test` exits 0
- [ ] app_state.dart reduced from ~512 lines to ~200 lines
- [ ] 4 new provider files created (sort_search, file_operations, recent_files, scanned_paths)
- [ ] HomeScreen uses SortSearchProvider for sort/search
- [ ] ViewerScreen uses FileOperationsProvider for decrypt/save
- [ ] No functionality regressions — all existing features work

## STOP conditions

- If app_state.dart is significantly different from the excerpts above, STOP and report drift
- If a verification step fails after 2 fix attempts, STOP and report
- If the split requires touching files outside the in-scope list, STOP and report
