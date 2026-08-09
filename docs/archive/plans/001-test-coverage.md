# Plan 001: Add real test coverage

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat abe2b97..HEAD -- test/ lib/services/ lib/providers/` — if files changed since, compare current code against excerpts; on mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `abe2b97`, 2026-06-13

## Why this matters

The app handles encryption (AES-256-GCM), file I/O, complex state management, and user data. Zero real tests means every regression ships silently. One bad encryption bug = data loss. Tests are foundational — everything else is safer with them.

## Current state

- Only `test/widget_test.dart` exists — 8 lines, asserts `1+1==2`
- Services are pure Dart with no Flutter dependency → unit-testable
- Providers extend `ChangeNotifier` → testable with `tester.pumpWidget()`

### Files to test (in priority order):

- `lib/services/encryption_service.dart` — AES-256-GCM encrypt/decrypt, PBKDF2 key derivation, wrong-passphrase rejection
- `lib/services/file_service.dart` — file scanning (recursive), read/write/delete operations
- `lib/services/tag_service.dart` — CRUD for tags, file-tag associations via SharedPreferences
- `lib/services/settings_service.dart` — settings persistence, key migration
- `lib/providers/tag_provider.dart` — tag CRUD via provider, active filter, file-tag resolution
- `lib/providers/encryption_provider.dart` — passphrase state machine, encrypt/decrypt orchestration
- `lib/providers/settings_provider.dart` — theme mode, last-read-page, auto-encrypt toggle
- `lib/providers/app_state.dart` — directory loading, file selection, search, sort, encryption flow, recent files

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Analyze | `dart analyze` | No issues found |
| Unit tests | `flutter test --no-sound-null-safety` or `flutter test` | All tests pass |
| Single test | `flutter test test/path/to/test.dart` | All pass |

## Scope

**In scope**: `test/` directory — create new test files matching `test/<service/provider>_test.dart` naming

**Out of scope**:
- Widget/integration tests (unit tests only for this plan)
- `lib/` source changes — do NOT modify production code
- UI tests for screens

## Steps

### Step 1: Create `test/encryption_service_test.dart`

Test `EncryptionService.encryptBytes()` and `decryptBytes()`:

- Encrypt then decrypt returns same bytes
- Wrong passphrase throws `EncryptionException`
- Corrupted data throws `EncryptionException`
- Empty bytes round-trips correctly
- Large payload (1MB random data) round-trips correctly

Pattern:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/services/encryption_service.dart';

void main() {
  group('EncryptionService', () {
    test('encrypt then decrypt returns original bytes', () {
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
      final encrypted = EncryptionService.encryptBytes(plaintext, 'test-pass');
      final decrypted = EncryptionService.decryptBytes(encrypted, 'test-pass');
      expect(decrypted, plaintext);
    });

    test('wrong passphrase throws EncryptionException', () {
      final plaintext = Uint8List.fromList([1, 2, 3]);
      final encrypted = EncryptionService.encryptBytes(plaintext, 'pass-a');
      expect(
        () => EncryptionService.decryptBytes(encrypted, 'pass-b'),
        throwsA(isA<EncryptionException>()),
      );
    });
  });
}
```

**Verify**: `flutter test test/encryption_service_test.dart` → all pass

### Step 2: Create `test/tag_service_test.dart`

Test `TagService` CRUD operations (runs on SharedPreferences mock or in-memory):

- Create tag, read back by ID
- Update tag name/color
- Delete tag
- Assign file to tag, check `getFilesForTag()`
- Remove file from tag
- `getAllTags()` returns all created tags

**Verify**: `flutter test test/tag_service_test.dart` → all pass

### Step 3: Create `test/settings_service_test.dart`

Test `SettingsService`:

- Set and get `lastDir`
- Set and get `lastReadPage` per file path
- Theme mode persistence (system/light/dark)
- Auto-encrypt toggle

**Verify**: `flutter test test/settings_service_test.dart` → all pass

### Step 4: Create `test/file_service_test.dart`

Test `FileService` (use temp directories):

- `scanDirectory()` finds .pdf files and ignores non-PDF
- `scanDirectoryRecursive()` finds PDFs in subdirectories
- `deleteFile()` removes file
- `isReadable()` returns true for existing dir, false for non-existent

**Verify**: `flutter test test/file_service_test.dart` → all pass

### Step 5: Create `test/tag_provider_test.dart`

Test `TagProvider`:

- Create tag notifies listeners
- Delete tag removes it and cleans up file associations
- Active filter returns only files with that tag
- `getResolvedTagsForFile()` returns correct tags
- `forgetFile()` removes all tag associations for a file path

Use `tester.pumpWidget()` or instantiate directly with mock SharedPreferences.

**Verify**: `flutter test test/tag_provider_test.dart` → all pass

### Step 6: Create `test/app_state_test.dart`

Test `AppState` (critical paths):

- `loadDirectory()` populates files
- Sort by name/modified/size works correctly
- Search query filters files
- `selectFile()`/`closeFile()` updates state
- `deleteFile()` removes file and notifies
- `setSearchQuery()` filters the file list
- `recentFilesInDir` cache is correct

**Verify**: `flutter test test/app_state_test.dart` → all pass

### Step 7: Final verification

Run `dart analyze` → 0 issues
Run `flutter test` → all tests pass

## Done criteria

- [ ] `dart analyze` exits 0
- [ ] `flutter test` exits 0, at least 50+ individual test cases
- [ ] No modifications to `lib/` directory
- [ ] `test/encryption_service_test.dart` exists with encrypt/decrypt round-trip + wrong-passphrase tests
- [ ] `test/tag_service_test.dart` exists with CRUD tests
- [ ] `test/settings_service_test.dart` exists with persistence tests
- [ ] `test/file_service_test.dart` exists with scan/delete tests
- [ ] `test/tag_provider_test.dart` exists with listener/filter tests
- [ ] `test/app_state_test.dart` exists with sort/search/select tests

## STOP conditions

- If `flutter test` requires a device/simulator (should run headless), STOP and report
- If tests depend on real filesystem at specific paths, STOP — use temp directories
- If any provider requires `WidgetsFlutterBinding.ensureInitialized()`, STOP and wrap in `TestWidgetsFlutterBinding.ensureInitialized()`
