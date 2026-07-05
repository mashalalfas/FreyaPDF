# FeyaPDF — Architecture & Security Score Report (V2 — Post-Fix Re-Score)

**Date:** 2026-07-05
**Codebase:** `~/Development/FeyaPDF/`
**Re-Score Scope:** `lib/` (56 Dart files, ~12,177 LOC) + `test/` (24 files, ~5,377 LOC) + `android/`

---

## TL;DR — Headline Numbers

| Metric | **V1 (pre-fix)** | **V2 (post-fix)** | **Δ** |
|---|---|---|---|
| Architecture | 6.4 / 10 (B-) | **7.9 / 10 (B+)** | **+1.5** |
| Security | 6.5 / 10 (B-) | **8.1 / 10 (A-)** | **+1.6** |
| **Combined** (60/40) | **6.4 / 10 (B Tier)** | **8.0 / 10 (A- Tier)** | **+1.6** |

**Tier change:** B → **A-**

**P0 blockers (V1):** ✅ Both resolved
1. ✅ Biometric passphrase now in `flutter_secure_storage` (Android Keystore)
2. ✅ Backup exports now AES-256-GCM encrypted (`.feya` format) with passphrase prompt

---

## Phase 1 — Architecture Score

### Methodology
Read all 56 source files in `lib/` plus `pubspec.yaml`, `AndroidManifest.xml`, and `analysis_options.yaml`. Evaluated against the architecture-pro framework's 8 quality dimensions.

### Breakdown

| # | Dimension | V1 | V2 | Notes |
|---|---|---|---|---|
| 1 | Separation of Concerns | 6 | **8** | `lib/core/`, `lib/features/*/`, `lib/shared/` triad in place. `EncryptionProvider` is correctly the single source of truth for passphrase. Minor issue: `BackupProvider` mixes UI dialog (`_promptPassphrase`, `_summaryRow`) with orchestration; should split. |
| 2 | Dependency Direction | 6 | **8** | Clear UI → Provider → Service layering. `EncryptionProvider` injected via `attachEncryption()` after first frame. `RecentFilesProvider` and `ScannedPathsProvider` still reach `SharedPreferences`/`FileSystem` directly, bypassing `SettingsService` — minor leak. |
| 3 | Single Responsibility | 6 | **7** | Most files are focused, but **three files are still oversized**: `viewer_screen.dart` (1298 LOC), `home_screen.dart` (968 LOC), `settings_screen.dart` (896 LOC). `secure_folder_card.dart` (514 LOC) bundles handler logic with presentation. Multi-purpose widgets inline dialogs. |
| 4 | Testability | 7 | **8** | Services are pure static methods with injectable deps (`BiometricPassphraseStorage({FlutterSecureStorage? storage})`). `BackupService` takes 4 service deps via constructor — fully mockable. 24 test files / 5,377 LOC = ~44% test/code ratio (lib+test). 360 tests total. Heavy `widget_test` and integration coverage. |
| 5 | State Management | 6 | **8** | `provider: ^6.1.0` used consistently. 31 `ChangeNotifier` subclasses. Cross-provider wiring via post-frame `attach*()` calls is a pragmatic, well-documented workaround for `EncryptionProvider` ↔ `SecureFolderProvider`/`FileOperationsProvider`. No Riverpod/BLoC migration needed at this scale. |
| 6 | Error Handling | 7 | **8** | Custom `EncryptionException` class. Decryption wraps internal exceptions in a generic `'Wrong passphrase or corrupted file'` — no info leak. Atomic temp-file-then-rename pattern in `EncryptionService.encryptFile`, `SecureFolderService.importFile/exportFile`, `EncryptionProvider.reEncryptFile`. **19 `debugPrint` calls remain** — fine for debug builds but could leak paths via logcat. Some `catch (_) {}` silently swallow errors in batch ops (`FileOperationsProvider.batchDelete`). |
| 7 | Code Duplication | 6 | **7** | Encrypt/decrypt paths exist in both `EncryptionProvider` and `SecureFolderProvider` — but `SecureFolderProvider` properly delegates to `SecureFolderService`. `passphrase_dialog.dart` and `biometric_unlock_dialog.dart` share a passphrase strength meter pattern but render slightly differently (justified). `path.split('/').last` repeated ~12 times — could be a helper. `FileOperationsProvider.shareFile()` and `batchShare()` both contain near-identical "decrypt → write temp → share" logic. |
| 8 | Naming Conventions | 8 | **9** | Strong consistency: `*Provider` for state, `*Service` for IO/crypto, `*Screen` / `*Dialog` / `*Card` for widgets. Slight confusion: `SecureFolder` (model), `SecureFolderService`, `SecureFolderProvider` all exist; the model class is essentially unused outside its file. |

**Architecture Subtotal:** 8 + 8 + 7 + 8 + 8 + 8 + 7 + 9 = **63 / 80 → 7.875 → 7.9 / 10**

---

## Phase 2 — Security Score

### Methodology
Read all encryption/security source files plus `AndroidManifest.xml`, `pubspec.yaml` (dependency versions), and re-evaluated the previously-flagged P0 blockers. Scored against the security-and-hardening framework's 9 dimensions.

### Breakdown

| # | Dimension | V1 | V2 | Notes |
|---|---|---|---|---|
| 1 | Encryption Implementation | 7 | **9** | **AES-256-GCM** (`encrypt: ^5.0.3`) with 12-byte IV, 32-byte salt, 600,000 PBKDF2-SHA256 iterations (matches OWASP 2023 guidance). Auth tag verified on decrypt. Backup format adds `FEYA` magic + version byte. **Downside:** App-lock PIN uses *single* SHA-256 (no PBKDF2/scrypt/Argon2) — see weakness #3. |
| 2 | Authentication | 6 | **8** | Biometric (`local_auth: ^3.0.1`) wired through `BiometricAuthService`. `authenticate()` uses `biometricOnly: true` and `sensitiveTransaction: true` for crypto-class prompts. App-lock gates the whole app via `AppLockGate` with `WidgetsBindingObserver` to re-lock on resume. PIN entry with shake animation, error feedback, haptic. **No rate-limiting / exponential backoff on PIN failures.** |
| 3 | Data at Rest | 4 | **9** | ✅ **Major V1→V2 fix:** `BiometricPassphraseStorage` (formerly plaintext `SharedPreferences` under `_feya_bio_passphrase`) now wraps `FlutterSecureStorage` (Android EncryptedSharedPreferences / iOS Keychain). One-time migration (`_migrateFromLegacyPrefsIfNeeded`) reads any legacy plaintext, copies to secure store, then `prefs.remove()`. PIN hash + salt also in secure storage. Encrypted PDFs in `FeyaPDF_Secure/`. **Minor:** `FeyaPDF_Exports/` contains plaintext PDFs (decrypted view of secure files). |
| 4 | Input Validation | 6 | **7** | Passphrase ≥8 chars + not in `commonPasswords` set. Magic byte validation before decryption. `BackupService.importFromJson` returns false on version mismatch. `PermissionService` checks Android SDK for permission branch. **Gap:** No max-length on passphrase (DoS via huge PBKDF2). No filename validation before file IO — relies on `FileService.isReadable()`. |
| 5 | Secrets Management | 9 | **10** | Zero hardcoded keys, tokens, or credentials in `lib/` (verified by grep). PBKDF2 derives keys at runtime from user passphrase + per-encryption salt. `Random.secure()` for IV/salt generation. No API keys anywhere. |
| 6 | Dependency Security | 7 | **8** | All deps recent (Jun 2024–Mar 2025 release window): `flutter_secure_storage: ^9.2.0`, `local_auth: ^3.0.1`, `encrypt: ^5.0.3`, `pointycastle: ^3.9.1`, `permission_handler: ^11.3.1`. No known critical CVEs in this matrix at audit time. `permission_handler` historically had CVE-2023-4630 — patched in current. Manifest declares only PDF-relevant permissions + storage. |
| 7 | Error Exposure | 6 | **6** | Encryption errors wrap to generic message (good). However: `EncryptionProvider.encryptFile('File not found: $pdfPath')` exposes file paths; `SecureFolderProvider._error = 'Failed to load secure files: $e'` propagates raw exception text to UI; `debugPrint('SecureFolderService: $e')` in 4 places leaks internal state via logcat in debug builds. |
| 8 | Permission Handling | 6 | **7** | `PermissionService` correctly branches on `DeviceInfoPlugin().androidInfo.version.sdkInt` (≥30 → MANAGE_EXTERNAL_STORAGE, else storage). Pre-prompt dialog explains rationale. Opens settings on denial. **High-risk surface:** `MANAGE_EXTERNAL_STORAGE` is broad; `requestLegacyExternalStorage="true"` is discouraged for API 30+ target. No `android:allowBackup="false"` set — defaults to true (secure storage keys are encrypted at rest but plaintext SharedPreferences can leak via `adb backup`). |
| 9 | Backup Security | 4 | **9** | ✅ **Major V1→V2 fix:** `BackupService.encryptBackupJson()` / `decryptBackupToJson()` wrap JSON in `FEYA` magic + AES-256-GCM payload. `BackupProvider.exportBackup()` requires user-supplied passphrase **with confirmation** (twice-typed). `importBackup()` reads bytes first, detects `looksEncrypted()` magic, then prompts for passphrase (3 attempts with retry counter). Plain-JSON legacy backups still accepted (intentional migration). Schema version validation prevents version-skew restores. |

**Security Subtotal:** 9 + 8 + 9 + 7 + 10 + 8 + 6 + 7 + 9 = **73 / 90 → 8.11 → 8.1 / 10**

---

## Phase 3 — Delta Analysis (V1 → V2)

### ✅ What Improved

| Area | V1 Issue | V2 Resolution | Impact |
|---|---|---|---|
| **Biometric passphrase storage** | Plaintext in `SharedPreferences` under `_feya_bio_passphrase` — root-readable XML | Migrated to `FlutterSecureStorage` (Android Keystore-backed EncryptedSharedPreferences). One-time legacy migration in `_migrateFromLegacyPrefsIfNeeded()`. | **+1.5** on Data at Rest |
| **Backup confidentiality** | Plain-JSON dump with no encryption; passphrase-free; full metadata exfiltration on backup loss | AES-256-GCM with PBKDF2-derived key, `FEYA` magic header, passphrase confirmation on export, 3-attempt retry on import, schema version validation | **+5.0** on Backup Security |
| **File organization** | Flat structure mixed providers/widgets/services | Feature-based layout: `core/features/shared` triad with widgets subfolders. 55 files restructured. | **+1.5** on Separation of Concerns |
| **Test coverage** | 340 tests | 360 tests (20 new) — including `biometric_passphrase_storage_test.dart`, `backup_encryption_test.dart`, `passphrase_strength_test.dart`, `failure_path_test.dart` | **+1.0** on Testability |
| **Bug fixes** | 8 known bugs (memory leaks in `IntentHandler`, race conditions in `FileOperationsProvider.shareFile`, false-success in `BookmarkProvider.forgetFile`, atomic write missing in `SecureFolderService`) | All 8 fixed in `FIX_SUMMARY_M3.md`. `flutter analyze`: 0 issues. | **+0.5** on Error Handling |
| **Viewer rendering** | Link annotation overlays + thumbnail layout broken (Expanded missing) | Removed overlays (pdfrx renders natively); thumbnails use `Expanded` + `BoxFit.contain`; TOC outline retries progressive loading | UX reliability +0.3 |
| **Lifecycle hardening** | No re-lock on resume; no WidgetsBindingObserver | `AppLockGate` observes lifecycle, re-locks on `AppLifecycleState.resumed` | **+0.5** on Authentication |

### ⚠️ What Did NOT Improve

| Area | V1 Status | V2 Status | Notes |
|---|---|---|---|
| **App-lock PIN hash** | Single SHA-256 | **Still single SHA-256** | `AppLockService._hashPin` uses one SHA-256 pass with 16-byte salt. For a 6-digit PIN (10⁶ keyspace), GPU offline attack on extracted secure storage is sub-second. Should use PBKDF2 or Argon2id at ≥100k iterations. |
| **Android `allowBackup`** | Not set (default true) | **Not set** | Missing `android:allowBackup="false"` and `<application android:fullBackupContent="@xml/backup_rules">`. ADB backup could exfiltrate SharedPreferences and `FeyaPDF_Secure/` plaintext (encrypted file contents are still safe due to GCM auth tag). |
| **MANAGE_EXTERNAL_STORAGE scope** | Requested | **Still requested** | High-risk permission. Should migrate to granular MediaStore / SAF for API 33+. |
| **Export dir cleanup** | Plaintext PDFs persisted | **Still persisted indefinitely** | `FeyaPDF_Exports/` is never pruned. After several exports, all decrypted PDFs accumulate. |
| **Temp file handling** | Decrypted bytes → temp file for sharing | **Still temp file** | `FileOperationsProvider.shareFile` and `batchShare` write plaintext PDFs to `getTemporaryDirectory()`. Not securely deleted after share. |
| **Error message hygiene** | Some paths in errors | **Some paths still in errors** | `EncryptionProvider` still includes `pdfPath` in error string; `SecureFolderProvider._error` still uses `$e` toString. |
| **Large-screen refactor** | viewer/home/settings already large | **Now 1298 / 968 / 896 LOC** | Restructuring didn't break these giant files down. |

---

## Top 5 Strengths (V2)

1. **Defense-in-depth crypto layer** — AES-256-GCM + PBKDF2-SHA256@600k + per-file salt + CSPRNG IV + atomic temp-file rename. Format is self-describing (`MELY`/`FEYA` magic + version byte). Same primitive is reused for both per-file encryption and backup encryption.
2. **App-wide authentication gate with biometric primary, PIN fallback** — `AppLockGate` + `AppLockService` + `BiometricAuthService` cover cold start, resume, and per-encrypted-file unlock paths. Biometric prompts use `biometricOnly: true` and `sensitiveTransaction: true`.
3. **Zero hardcoded secrets + no telemetry + no network** — Audited `lib/` and `pubspec.yaml`. No API keys, no OAuth tokens, no analytics SDK, no HTTP client. Surface area is purely local filesystem + OS secure storage.
4. **Pragmatic Provider architecture with explicit cross-provider wiring** — `attachEncryption()`, `attachSortSearch()`, `attachScannedPaths()` make data-flow dependencies auditable. `EncryptionProvider` is correctly the single source of truth for the passphrase (removed from `SettingsService`).
5. **Strong test discipline with realistic failure-path coverage** — 360 tests across services, providers, and widgets. `failure_path_test.dart` specifically targets negative scenarios; `biometric_passphrase_storage_test.dart` covers the secure-storage migration; `backup_encryption_test.dart` covers the full export → encrypt → decrypt → import round-trip.

---

## Top 5 Remaining Weaknesses

1. **App-lock PIN hash is brute-forceable** (`AppLockService._hashPin`) — Single SHA-256 + 16-byte salt. With 6-digit PIN (10⁶ space) and GPU offline attack on a stolen `flutter_secure_storage` extract, the PIN is recovered in milliseconds. **Should use PBKDF2-SHA256@≥100k or Argon2id.**
2. **Three god-screens remain** — `viewer_screen.dart` (1298 LOC), `home_screen.dart` (968 LOC), `settings_screen.dart` (896 LOC). State management + widget tree + dialogs + handlers all in one file. Future feature work in any of these files is high-risk for regressions.
3. **Decrypted PDF persistence in three locations** — `FeyaPDF_Exports/`, `getTemporaryDirectory()` for share, and the `FeyaPDF_Secure/` after export. None are auto-purged. A user who exports a "secret.pdf" leaves a plaintext copy behind unless they manually clean it up.
4. **Android manifest missing `allowBackup="false"`** — Default Android behavior allows ADB backup of app data, including SharedPreferences (favorites, recent files paths, tags, last-read positions) and `FeyaPDF_Secure/` (encrypted but still copied). Combined with `MANAGE_EXTERNAL_STORAGE` and `requestLegacyExternalStorage="true"`, the manifest is permissive.
5. **Error messages and `debugPrint` leak internal state** — 19 `debugPrint` calls in services log raw exception messages (often containing file paths and stack frames). Several `EncryptionProvider`/`SecureFolderProvider` error strings include `$pdfPath` or `$e.toString()`. Fine in debug, but paths and exception detail can aid a forensic attacker with a debug build.

---

## Top 5 Recommendations (Prioritized)

### 🥇 P0 — Address Immediately

**R1. Upgrade app-lock PIN hash to PBKDF2 / Argon2id**
- File: `lib/features/security/app_lock_service.dart`
- Change `_hashPin` from single `SHA256Digest().process(utf8.encode('$salt:$pin'))` to `PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))` with ≥100k iterations, matching the encryption primitive in `EncryptionService._deriveKey`.
- Migrate existing PINs on next successful verify (re-stretch + write).
- Impact: closes the offline brute-force vector on app-lock PIN. Low risk, ~30 LOC change.

### 🥈 P1 — High Value, Low Risk

**R2. Add `android:allowBackup="false"` to AndroidManifest.xml + extract-level rules**
- File: `android/app/src/main/AndroidManifest.xml`
- Add `android:allowBackup="false"` and `android:fullBackupContent="@xml/backup_rules"` to `<application>`.
- Create `android/app/src/main/res/xml/backup_rules.xml` explicitly excluding `FeyaPDF_Secure/` and `FeyaPDF_Exports/`.
- Impact: removes ADB backup as a data-exfiltration channel. ~10 LOC.

**R3. Auto-purge `FeyaPDF_Exports/` and share temp files**
- Files: `secure_folder_card.dart`, `file_operations_provider.dart`
- On `shareFile`/`batchShare`, write to `getTemporaryDirectory()` then schedule a delete after `share_plus` completes (or after 1 hour via `Timer`). On secure-folder export, prompt "Delete the exported copy?" after sharing.
- Impact: closes the plaintext-leak window for decrypted exports.

### 🥉 P2 — Maintenance

**R4. Refactor the three god-screens**
- Split `viewer_screen.dart` (1298 LOC) into: `viewer_screen.dart` (orchestrator) + `widgets/viewer_toolbar.dart` + `widgets/viewer_outline_panel.dart` + `providers/outline_provider.dart` (retry logic for progressive loading).
- Split `home_screen.dart` (968 LOC) into: `home_screen.dart` + `widgets/home_filter_bar.dart` + `widgets/home_empty_state.dart`.
- Split `settings_screen.dart` (896 LOC) into per-feature sections (theme, security, backup, etc.).
- Impact: reduces regression risk, improves diff readability, makes widgets individually testable.

**R5. Sanitize error messages and gate debug logs**
- Files: `EncryptionProvider`, `SecureFolderProvider`, `SecureFolderService`, all `debugPrint` sites.
- Strip file paths from user-facing errors: `'File not found'` instead of `'File not found: $pdfPath'`.
- Gate `debugPrint` behind `kDebugMode` or a `LoggingService` that strips PII in release builds.
- Impact: reduces info leakage in both debug logs and production error toasts.

---

## Verification Commands

To re-verify the V2 score independently:

```bash
cd ~/Development/FeyaPDF

# 1. Confirm zero analyzer issues
flutter analyze

# 2. Confirm 360 tests pass
flutter test --reporter compact

# 3. Confirm no plaintext passphrase storage (was the V1 P0)
grep -rn "_feya_bio_passphrase\|setString.*passphrase" lib/

# 4. Confirm encrypted backup format
grep -n "_encryptedMagic\|FEYA\|encryptBackupJson" lib/features/settings/backup_service.dart

# 5. Confirm crypto primitives
grep -n "AES\|PBKDF2\|GCM\|Random.secure" lib/features/encryption/encryption_service.dart

# 6. Confirm Android manifest
cat android/app/src/main/AndroidManifest.xml
```

---

## Score Distribution (V2)

```
Architecture:  7.9 / 10  ████████████████████░░░░░  (B+)
Security:      8.1 / 10  █████████████████████░░░░  (A-)
─────────────────────────────────────────────────────
COMBINED:      8.0 / 10  ████████████████████░░░░░  (A-)
```

**Tier letter grades:**
- Architecture: **B+** (Good — production-ready, but refactor opportunities remain in 3 large screens)
- Security: **A-** (Strong — major P0s closed, only hardening gaps remain)
- Combined: **A-** (Up from B; ready for production release with R1/R2/R3 follow-up)

---

## Files Reviewed (56 lib + 24 test)

**Core:** `core/models/pdf_file.dart`, `shared/widgets/lottie_route.dart`, `theme.dart`, `main.dart`
**Encryption (4 files, 327 LOC):** `encryption_service.dart`, `encryption_provider.dart`, `passphrase_strength.dart`, `widgets/passphrase_dialog.dart`
**Security (8 files, 1,512 LOC):** `app_lock_service.dart`, `biometric_auth_service.dart`, `biometric_passphrase_storage.dart`, `secure_folder.dart`, `secure_folder_service.dart`, `secure_folder_provider.dart`, `widgets/app_lock_screen.dart`, `widgets/biometric_unlock_dialog.dart`, `widgets/secure_folder_card.dart`, `widgets/secure_folder_import_dialog.dart`
**File management (13 files):** `app_state.dart`, `file_service.dart`, `permission_service.dart`, `intent_handler.dart`, `recent_files_provider.dart`, `scanned_paths_provider.dart`, `selection_provider.dart`, `sort_search_provider.dart`, `favorites_provider.dart`, `file_operations_provider.dart`, `home_screen.dart`, `widgets/*`
**Viewer (5 files):** `viewer_screen.dart`, `page_navigation.dart`, `providers/search_provider.dart`, `widgets/*`
**Bookmarks / Highlights / Tags (9 files):** all `*.dart` under each feature
**Settings (3 files):** `settings_service.dart`, `settings_provider.dart`, `user_profile.dart`, `backup_service.dart`, `backup_provider.dart`
**Tests (24 files):** all under `test/`

— End of report —