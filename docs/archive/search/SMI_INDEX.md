# FeyaPDF — SMI Index

## Project Info
- **Name:** Feya PDF
- **Stack:** Flutter/Dart, Android
- **Location:** ~/Development/FeyaPDF/
- **Status:** Active — v1.2
- **Created:** 2026-06-03

## Milestones

### #1 — Initial Build (2026-06-03)
- PDF reader with E2E encryption (AES-256-GCM, .pdf.enc format)
- Tagging system with 8-color palette, filter bar, management screen
- Native Android intent handler for "Open with" support
- Runtime storage permissions for Android 11+ (MANAGE_EXTERNAL_STORAGE)
- Recursive file scanning with Isolate
- Share via share_plus (decrypted for encrypted files)
- Last-read position persistence per file
- flutter analyze: clean
- APK: 52.5MB
- GDrive: https://drive.google.com/open?id=1fwXx8yA-A5K4UfIBb_QZdTjuZsd24bLg

### #2 — Phase 2 (2026-06-17, commit `0c4edbf`)
- Full PDF text search engine with result navigation (find next/previous)
- Dark mode theme for night reading
- Thumbnail grid for visual page overview
- Text selection and copy from PDF pages
- Bottom navigation bar redesign
- PDF outline/TOC sidebar
- Continuous scroll mode
- Passphrase strength indicator

### #3 — Phase 3 (2026-06-17, commit `464afe4`)
- **Text highlighting** with persistence — create, view, delete highlights per document
- **Biometric unlock** — face, fingerprint, iris authentication
- **App lock** — PIN-based lock screen with biometric fallback
- 42 new tests (17 highlight + 8 biometric + 17 app lock)
- 19 files, 3,017 additions, 0 analyze issues

## Architecture
- **Models:** PdfFile, Tag, UserProfile, HighlightData
- **Services:** FileService, EncryptionService, SettingsService, TagService, PermissionService, IntentHandler, HighlightService, AppLockService, BiometricAuthService
- **Providers:** AppState, EncryptionProvider, SettingsProvider, TagProvider, HighlightProvider
- **Screens:** HomeScreen, ViewerScreen, SettingsScreen, TagsScreen
- **Widgets:** FileListTile, EncryptionBadge, PassphraseDialog, TagChip, TagPickerDialog, LottieRoute, AppLockScreen, BiometricUnlockDialog, HighlightsPanel

## Design Language
- Teal #00897B primary, amber secondary
- Warm beige #FBF8F1 light bg, dark gray #1A1C1E dark bg
- Material You, Google Fonts Inter
- Hero transitions, stagger animations
- Matches FeyaMD design system exactly

## Dependencies
- flutter, provider, google_fonts, url_launcher, intl
- encrypt, pointycastle (AES-256-GCM encryption)
- shared_preferences (persistence)
- permission_handler, device_info_plus (permissions)
- pdfrx (PDF rendering)
- share_plus (file sharing)
- file_picker, path_provider, lottie
- local_auth (biometric authentication)
- flutter_secure_storage (secure credential storage)

## Lessons Learned
- Army protocol: max 2-3 files per soldier, decompose before spawning
- Don't give full builds to single agents — slice by layer
