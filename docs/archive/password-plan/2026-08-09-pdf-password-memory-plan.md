# Remembered PDF Passwords Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use flutter-craft:flutter-executing to implement this plan task-by-task.

**Goal:** Let users unlock standard password-protected PDFs and optionally remember each password securely for that file.

**Architecture:** Existing Provider architecture with a dedicated secure-storage data service and a viewer-scoped password prompt.

**Dependencies:** Existing `flutter_secure_storage` and `pdfrx`; no new packages.

---

### Task 1: Per-file secure password storage

**Layer:** Data

**Files:**
- Create: `lib/features/security/pdf_password_storage.dart`
- Test: `test/pdf_password_storage_test.dart`

**Implementation:** Store passwords in secure storage under a deterministic hash of the normalized absolute file path. Expose read, write, and delete operations. Never include these secrets in SharedPreferences, backups, logs, or exported settings.

**Verification:** Unit-test empty storage, write/read, overwrite, delete, and distinct file keys with a mocked `FlutterSecureStorage`.

### Task 2: Password prompt and remember choice

**Layer:** Presentation

**Files:**
- Create: `lib/features/viewer/widgets/pdf_password_dialog.dart`
- Test: `test/pdf_password_dialog_test.dart`

**Implementation:** Add a neutral PDF-password dialog with obscured input, cancel, submit, and a “Remember password for this file” checkbox. Do not reuse the FeyaPDF encryption passphrase dialog because PDF passwords may be short or common.

**Verification:** Widget-test submit, cancel, obscured input, and checkbox state.

### Task 3: Wire pdfrx password callbacks into the viewer

**Layer:** Presentation / Integration

**Files:**
- Modify: `lib/features/viewer/viewer_screen.dart`
- Modify: `lib/features/viewer/providers/search_document_provider.dart`

**Implementation:** Pass a shared `PdfPasswordProvider` to both `PdfDocumentRefFile`/`PdfDocumentRefData` and the search document. Try a remembered password once, otherwise show the dialog. Bound retries, handle cancellation, save only after `onViewerReady` confirms a successful document, and use a source-key revision when retrying after a failed password. Keep this separate from `.pdf.enc` decryption.

**Verification:** Confirm normal PDFs remain unchanged; test password callback cancellation and retry state without persisting secrets.

### Task 4: Forget remembered passwords

**Layer:** Presentation

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`
- Modify: `lib/features/security/pdf_password_storage.dart`

**Implementation:** Add a settings action to clear all remembered PDF passwords. Delete per-file remembered passwords when a file is deleted or renamed if those flows expose a stable path update.

**Verification:** Test that clearing removes stored entries and does not affect the app’s own encryption passphrase.

### Task 5: Full verification

**Layer:** Test / Integration

**Files:**
- Modify: `test/viewer_integration_test.dart`

**Implementation:** Add coverage for password-provider wiring and a real encrypted-PDF device fixture when available. Keep the existing headless tests native-PDFium-safe.

**Verification:** Run `flutter analyze`, the focused tests, the serial full suite, and `flutter build apk --debug`.
