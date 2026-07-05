# FIX SUMMARY 003 — Test Failures, Analyze Warnings, and Doc Corrections

**Date:** 2026-07-05
**Files Changed:** `test/viewer_integration_test.dart`, `test/widget_test.dart`, `lib/providers/backup_provider.dart`, `lib/screens/home_screen.dart`, `lib/services/permission_service.dart`

---

## Overview

Five issues spanning 5 files: 5 failing widget tests caused by missing provider registrations, 2 `dart analyze` warnings from BuildContext misuse across async gaps, and a misleading permission comment.

## Changes Applied

### File 1: `test/viewer_integration_test.dart`

#### Fix 1 — Added missing `HighlightProvider` and `BookmarkProvider` to test harness
**`_pumpViewer` function**

`ViewerScreen.initState` calls `context.read<HighlightProvider>()` and `context.read<BookmarkProvider>()` via `addPostFrameCallback`. The test's `MultiProvider` didn't include either, causing `ProviderNotFoundException` on 3 tests.

Added imports for `HighlightProvider`, `BookmarkProvider`, `HighlightService`, `BookmarkService`. Added both providers to the `MultiProvider`, constructing services with the existing `prefs` instance:

```dart
ChangeNotifierProvider<HighlightProvider>(
  create: (_) => HighlightProvider(HighlightService(prefs)),
),
ChangeNotifierProvider<BookmarkProvider>(
  create: (_) => BookmarkProvider(BookmarkService(prefs)),
),
```

**Impact:** Fixed 3 failing tests:
- `ViewerScreen — AppBar for encrypted files shows lock icon and displayName`
- `ViewerScreen — AppBar for encrypted files AppBar title does not show .enc suffix`
- `ViewerScreen — decryption failure path` (was skipping due to earlier exception cascade)

---

### File 2: `test/widget_test.dart`

#### Fix 2 — Synced provider list with `main.dart` production setup

The smoke tests provided 9 providers but `main.dart` now registers 14. Five were missing: `HighlightProvider`, `BookmarkProvider`, `BackupProvider`, `FavoritesProvider`, `SelectionProvider`.

Added all missing providers with proper service dependencies:

```dart
ChangeNotifierProvider(create: (_) => HighlightProvider(highlightService)),
ChangeNotifierProvider(create: (_) => BookmarkProvider(bookmarkService)),
ChangeNotifierProvider(create: (_) => BackupProvider(backupService)),
ChangeNotifierProvider(create: (_) => FavoritesProvider(settingsService)),
ChangeNotifierProvider(create: (_) => SelectionProvider()),
```

**Impact:** Fixed 2 failing tests:
- `FeyaPdfApp builds without throwing`
- `FeyaPdfApp shows a MaterialApp on first frame`

---

### File 3: `lib/providers/backup_provider.dart`

#### Fix 3 — Added `mounted` guard before `showDialog` after async gap
**Line 156**

`importBackup()` has multiple `await` calls (file picker, file read, JSON parse) before calling `showDialog(context: context)`. The `context` could be stale if the widget was disposed during the async operations.

```dart
// Step 4: Confirmation dialog
if (!context.mounted) return;
final confirmed = await showDialog<bool>(
```

**Impact:** Resolves `use_build_context_synchronously` analyzer warning.

---

### File 4: `lib/screens/home_screen.dart`

#### Fix 4 — Moved provider reads before async gap
**`_deleteFile` method, lines 151–162**

`context.read<BookmarkProvider>()` was called after two `await` calls (`fileOps.deleteFile` and `tagProvider.forgetFile`), guarded by `context.mounted` — which the analyzer flagged as an unrelated mounted check.

Moved the `context.read` call before the `await` chain so the provider reference is captured synchronously:

```dart
final bookmarkProvider = context.read<BookmarkProvider>();  // before await
final success = await fileOps.deleteFile(file);
if (success) {
  await tagProvider.forgetFile(file.path);
  bookmarkProvider.forgetFile(file.path);  // uses captured reference
}
```

**Impact:** Resolves `use_build_context_synchronously` analyzer warning. No behavioral change.

---

### File 5: `lib/services/permission_service.dart`

#### Fix 5 — Corrected misleading permission dialog comment
**Line 37**

The comment stated "This will show a dialog explaining why we need it" — but `Permission.manageExternalStorage.request()` does NOT show a dialog on Android 11+. It silently returns `isGranted` or `isDenied`. Users must manually navigate to Settings → Apps → Special Access → All Files Access.

```dart
// Request — on Android 11+ this does NOT show a dialog; it returns
// isGranted if already granted or isDenied otherwise. The user must
// navigate to Settings → Apps → Special Access → All Files Access.
final result = await Permission.manageExternalStorage.request();
```

**Impact:** Corrects developer-facing documentation. No behavioral change.

---

## Verification

### Dart Analysis
```
dart analyze → No issues found.
```

### Full Test Suite
```
flutter test → 340 passed, 4 skipped, 0 failed
```

### Before/After

| Metric | Before | After |
|--------|--------|-------|
| Tests passing | 335 | 340 |
| Tests failing | 5 | 0 |
| Analyze issues | 2 | 0 |
| Skipped (pre-existing) | 4 | 4 |

---

## Related Documents

- **BUG_REPORT_001.md** — Original silent folder scanning failure report
- **FIX_SUMMARY_001.md** — Isolate error collection, cache fixes (6 of 6 silent points)
- **FIX_SUMMARY_002.md** — Failure-path test coverage (13 tests)
- **FIX_SUMMARY_003.md** — This document (test harness sync, analyze fixes, doc correction)
