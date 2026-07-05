# FIX_SUMMARY_004 — 2026-07-05

Three issues fixed in the FeyaPDF Flutter project.

## Issue 1 (P0) — Biometric passphrase in plain SharedPreferences

**File:** `lib/features/security/widgets/biometric_unlock_dialog.dart`,
`lib/features/encryption/encryption_provider.dart`

**What changed**
- New helper `lib/features/security/biometric_passphrase_storage.dart`
  that wraps `FlutterSecureStorage` (Android Keystore-backed at rest) for
  reading/writing/clearing the biometric passphrase.
- `BiometricUnlockDialog` and `EncryptionProvider.clearPassphrase` now
  read/write through the new helper instead of `SharedPreferences`.
- One-time migration from the legacy SharedPreferences key
  (`_feya_bio_passphrase`) into secure storage runs on first read; the
  legacy plaintext entry is erased in the process.
- Existing `clearStoredBioPassphrase()` top-level helper still works
  (now delegates to the new helper).

**Why it matters**
On a rooted Android device the old `SharedPreferences` XML file could be
read by any process, exposing the encryption passphrase. The new
implementation keeps the same AES-256-GCM scheme but stores the secret
in `EncryptedSharedPreferences` backed by the Android Keystore.

## Issue 2 (P0) — Backups were plain-text JSON

**Files:** `lib/features/settings/backup_service.dart`,
`lib/features/settings/backup_provider.dart`

**What changed**
- `BackupService` gained two static helpers:
  - `looksEncrypted(bytes)` — detects a `FEYA` 4-byte magic header that
    prefixes every encrypted `.feya` backup.
  - `encryptBackupJson(json, passphrase)` → `Uint8List`
  - `decryptBackupToJson(bytes, passphrase)` → `String`
- Both wrap the existing `EncryptionService` (AES-256-GCM, 600 000
  PBKDF2 iterations) so backups use the same primitive as PDF encryption.
- `BackupProvider.exportBackup()`:
  - Prompts for a passphrase (with confirm field) via a new internal
    `_promptPassphrase()` helper.
  - Encrypts the JSON, writes a `.feya` file, shares it.
- `BackupProvider.importBackup()`:
  - File picker now accepts both `.feya` and `.json` extensions.
  - Reads the file as bytes, runs `looksEncrypted()`.
  - If encrypted: up to 3 prompts for the passphrase, then AES-GCM
    decryption before the existing JSON import path.
  - If plain: falls through to the legacy decoder (backward compatible).

## Issue 3 — Pale blue link overlay boxes

**File:** `lib/features/viewer/viewer_screen.dart`

**What changed**
- The `pageOverlaysBuilder` callback in `PdfViewerParams` used to draw a
  pale-blue translucent rectangle with a blue border for every link
  annotation. On PDFs with many links (or form fields interpreted as
  links) this produced the "blue boxes everywhere" effect.
- pdfrx already renders link annotations natively via
  `PdfAnnotationRenderingMode.annotationAndForms` (the default), so
  removing the overlay does not break link interactivity.
- The callback now returns `const []` for any page (link metadata is
  still cached in `_pageLinks` for future feature work, but no visible
  rectangles are painted on the PDF canvas any more).

## Tests

- New `test/biometric_passphrase_storage_test.dart` — 8 cases covering
  read/write/clear plus the legacy-key migration path (including the
  "secure value already present, ignore legacy" branch).
- New `test/backup_encryption_test.dart` — 12 cases covering magic
  detection, encrypt/decrypt round-trip, wrong-passphrase failure,
  ciphertext divergence on repeated calls, and end-to-end
  export → encrypt → decrypt → import.
- All pre-existing tests still pass; the existing
  `backup_service_test.dart` and `widget_test.dart` were untouched and
  continue to cover the plain-JSON path.

## Verification

```
$ flutter analyze
No issues found! (ran in 5.9s)

$ flutter test
All tests passed!   (+360 / ~4)
```

End-to-end tests for the new dialog behavior in `BackupProvider.export/import`
are out of scope for this fix (they require a `BuildContext` and `Share`/
`FilePicker` mocks); the unit-level coverage above proves the encryption
contract end-to-end.
