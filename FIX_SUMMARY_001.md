# FIX SUMMARY 001 — Silent Folder Scanning Failures

**Date:** 2026-06-15
**Bug Report:** BUG_REPORT_001.md
**Files Changed:** `lib/providers/app_state.dart`, `lib/services/file_service.dart`

---

## Overview

Six silent failure points conspired to make directory scanning errors completely invisible. When filesystem or permission errors occurred during folder scanning, users saw "No PDFs found" with zero diagnostic trail — even when their PDF files existed and folders were intact.

## Changes Applied

### File 1: `lib/providers/app_state.dart`

#### Fix 1 — Replaced silent `catch (_) {}` with logged error handling (SILENT POINT #2)
**Line 113 → now ~124**

```dart
// BEFORE:
} catch (_) {}

// AFTER:
} catch (e) {
  debugPrint('AppState: failed to scan directory $path: $e');
  return <PdfFile>[];
}
```

**Impact:** `loadAllDirectories` now logs every scan failure instead of silently swallowing all exceptions (`FileSystemException`, `IsolateSpawnException`, etc.).

#### Fix 2 — Don't cache empty results from potentially-failed scans (SILENT POINT #5)
**In `loadDirectory` (line ~55) and `loadAllDirectories` (line ~107)**

```dart
// BEFORE:
_fileCache[path] = List.unmodifiable(dirFiles);  // always cached

// AFTER:
if (dirFiles.isNotEmpty) {
  _fileCache[path] = List.unmodifiable(dirFiles);  // only cache non-empty
}
```

**Impact:** Failed scans that return `[]` no longer poison the cache. Re-opening the same folder after fixing permissions will trigger a fresh scan instead of returning the stale empty result.

#### Fix 3 — Added `invalidateCache()` method
**New method on AppState**

```dart
void invalidateCache() {
  _fileCache.clear();
  notifyListeners();
}
```

**Impact:** Callers (e.g., app resume handler) can now clear stale cache entries when permissions may have changed while the app was backgrounded. Previously the only way to clear cache was `refresh()` (pull-to-refresh).

### File 2: `lib/services/file_service.dart`

#### Fix 4 — Extracted isolate errors to main thread via `_ScanResult` class (SILENT POINT #1)
**`scanDirectoryRecursive` method**

Added a private `_ScanResult` class that bundles `files` + `errors`. Inside the isolate, all `debugPrint()` calls were replaced with `errors.add()`. After the isolate completes, errors are logged from the main thread where `debugPrint` is visible:

```dart
// BEFORE (invisible — debugPrint in isolate is lost):
debugPrint('FileService: error listing directory ${entry.path}: $e');

// AFTER:
// Inside isolate: errors.add('FileService: error listing directory ${entry.path}: $e');
// After isolate, on main thread:
for (final error in result.errors) {
  debugPrint('FileService: $error');  // visible in logcat/console
}
```

**Impact:** All filesystem errors, permission failures, and corrupt file exceptions that occur during recursive scanning are now visible in the debug output. This was the most insidious bug — the code was "handling" errors correctly but the logging was completely invisible.

#### Fix 5 — Added logging to `isReadable()` (SILENT POINT #4)
**Line ~134**

```dart
// BEFORE:
} catch (_) {
  return false;
}

// AFTER:
} catch (e) {
  debugPrint('FileService.isReadable: $path → $e');
  return false;
}
```

**Impact:** On Android scoped storage, `dir.list()` can throw `FileSystemException: Permission denied` even when `dir.exists()` returns `true`. This exception is now logged, making permission issues diagnosable.

#### Fix 6 — Added error collection for `existsSync()` failure in isolate (SILENT POINT #3)
**Line ~47**

```dart
// BEFORE:
if (!dir.existsSync()) return <PdfFile>[];

// AFTER:
if (!dir.existsSync()) {
  errors.add('Directory does not exist or not accessible: $dirPath');
  return _ScanResult([], errors);
}
```

**Impact:** On Android 11+ with scoped storage, `Directory.existsSync()` can return `false` for paths that DO exist but to which the app lacks permission. This is now logged as an explicit error instead of silently returning an empty list.

---

## Verification

### Dart Analysis
```
dart analyze lib/providers/app_state.dart lib/services/file_service.dart
→ No issues found.
```

### Flutter Tests
```
flutter test test/app_state_test.dart test/file_service_test.dart
→ 29/29 tests passed (0 failures, 0 skipped)
```

Full test suite: 104 passed, 4 skipped (pre-existing encryption skips + OOM on large payload — not related to these changes).

### New Error Visibility Confirmed
Test output now shows errors that were previously invisible:
```
FileService: Directory does not exist or not accessible: /no/such/dir
```

---

## What Was NOT Changed (per constraints)

- No public API signatures changed — all changes are internal
- `_ScanEntry` class preserved as-is
- `scanDirectory` (non-recursive) keeps `debugPrint` since it runs on main thread
- `deleteFile`, `renameFile` catch blocks left as-is (not in scanning pipeline)
- `home_screen.dart` fallback chain (SILENT POINT #6) not modified per task scope
- `permission_service.dart` not modified per task scope

---

## Remaining Work (from BUG_REPORT_001.md not addressed in this fix)

| Item | File | Priority | Status |
|------|------|----------|--------|
| Fix `_loadInitialData` fallback chain so Path B runs if Path A fails silently | `home_screen.dart` | High | ✅ Done (lines 61–68) |
| Fix misleading comment about permission dialog + add `openAppSettings()` | `permission_service.dart` | Medium | ✅ Comment fixed in FIX_SUMMARY_003 |
| Verify `MANAGE_EXTERNAL_STORAGE` before spawning isolate | `file_service.dart` | Medium | Open |
