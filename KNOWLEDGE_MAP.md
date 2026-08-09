# FeyaPDF Knowledge Map

> Updated from graphify code analysis (2026-08-09, commit `02cc1f46`) — 2,283 nodes, 3,570 edges, 125 communities. This refresh used deterministic AST extraction; semantic document extraction requires an LLM API key.

## Current Release

- **Version:** 1.2.0 (build 6)
- **Release commit:** `02cc1f4` (`release: v1.2.0`)
- **Verification:** `flutter analyze` clean; 392 tests passed
- **Device status:** Search opens and returns results after the duplicate `FocusNode` attachment was removed from the search bar.

## High-Level Architecture

FeyaPDF is a Flutter-based PDF reader with advanced features including encryption, bookmarks, highlights, tags, and secure folder management. The architecture follows a provider-based state management pattern with clear separation of concerns.

### Core Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                        │
│  (Screens, Widgets, UI Components)                          │
├─────────────────────────────────────────────────────────────┤
│                    Business Logic Layer                      │
│  (Providers, Services, State Management)                    │
├─────────────────────────────────────────────────────────────┤
│                    Data Layer                                │
│  (Models, Storage, Encryption, File System)                 │
└─────────────────────────────────────────────────────────────┘
```

## Core Modules

### 1. **PDF Viewer & Search** (Primary Module)
The largest module handling PDF rendering, navigation, and search functionality.

**Key Components:**
- `viewer_screen` — Main PDF viewing interface (28 edges, high centrality)
- `search_provider` — Search state management
- `search_bar` — Search input and result controls
- `page_navigation` — Page turn controls
- `thumbnail_grid` — Page thumbnail previews

**Dependencies:**
- Depends on: Bookmarks, Highlights, Security, File Management
- Used by: Home Screen, App Entry Point

### 2. **File Management** (Core Infrastructure)
Handles file operations, directory navigation, and file metadata.

**Key Components:**
- `home_screen` — Main file browser interface (32 edges, highest centrality)
- `file_operations_provider` — File CRUD operations (25 edges)
- `file_service` — Low-level file system operations
- `sort_search_provider` — File sorting and filtering
- `permission_service` — Storage permission handling

**Dependencies:**
- Depends on: Security (for encrypted files), Tags (for file tagging)
- Used by: PDF Viewer, Bookmarks, Highlights

### 3. **Security & Encryption** (Cross-Cutting Concern)
Provides encryption, biometric authentication, and secure storage.

**Key Components:**
- `encryption_service` — AES encryption/decryption
- `encryption_provider` — Encryption state management
- `biometric_auth_service` — Biometric authentication
- `app_lock_service` — App lock functionality
- `secure_folder` — Secure folder management
- `pdf_password_storage` — Secure per-file remembered PDF passwords
- `pdf_password_dialog` — Password prompt and remember-choice UI

**Dependencies:**
- Depends on: FlutterSecureStorage, local_auth
- Used by: File Management, PDF Viewer, Backup

### 4. **Bookmarks** (Feature Module)
PDF bookmark management with persistence.

**Key Components:**
- `bookmark_provider` — Bookmark state (23 edges)
- `bookmark_service` — Bookmark CRUD operations
- `bookmarks_panel` — Bookmark UI
- `bookmark` — Bookmark data model

**Dependencies:**
- Depends on: File Management (file paths), Security (encryption)
- Used by: PDF Viewer

### 5. **Highlights** (Feature Module)
PDF highlight/annotation system.

**Key Components:**
- `highlight_provider` — Highlight state (29 edges)
- `highlight_service` — Highlight CRUD operations
- `highlights_panel` — Highlight UI
- `highlight_data` — Highlight data model

**Dependencies:**
- Depends on: File Management, Security
- Used by: PDF Viewer

### 6. **Tags** (Feature Module)
File tagging and categorization system.

**Key Components:**
- `tag_provider` — Tag state management
- `tag_service` — Tag CRUD operations
- `tag_picker_dialog` — Tag selection UI
- `tag` — Tag data model

**Dependencies:**
- Depends on: File Management
- Used by: Home Screen, File List

### 7. **Settings & Profile** (Configuration Module)
App settings and user profile management.

**Key Components:**
- `settings_service` — Settings persistence (26 edges)
- `settings_provider` — Settings state (24 edges)
- `user_profile` — User profile model
- `app_state` — Global app state (25 edges)

**Dependencies:**
- Depends on: SharedPreferences
- Used by: All modules (configuration)

### 8. **App Updates** (Infrastructure)
GitHub-based app update system.

**Key Components:**
- `update_service` — Update checking and download
- `update_provider` — Update state management
- `github_release` — GitHub release model

**Dependencies:**
- Depends on: http package, GitHub API
- Used by: Settings

## God Nodes (Most Connected)

These are the central hubs of the architecture:

1. **`home_screen`** (32 edges) — Central file browser, connects to all file operations
2. **`main`** (31 edges) — App entry point, initializes all providers
3. **`highlight_provider`** (29 edges) — Highlight state hub
4. **`viewer_screen`** (28 edges) — PDF viewer hub
5. **`settings_service`** (26 edges) — Configuration hub
6. **`app_state`** (25 edges) — Global state hub
7. **`file_operations_provider`** (25 edges) — File operations hub
8. **`BookmarkProvider`** (24 edges) — Bookmark state hub
9. **`settings_provider`** (24 edges) — Settings state hub
10. **`bookmark_provider`** (23 edges) — Bookmark state hub

## Data Flow

```
User Action → Screen/Widget → Provider → Service → Storage/Encryption
     ↑                                                    ↓
     └────────────────── UI Update ←──────────────────────┘
```

### Typical PDF Open Flow:
1. `home_screen` → `file_operations_provider` → `file_service`
2. `file_service` → `encryption_service` (if encrypted)
3. `encryption_service` → `viewer_screen`
4. `viewer_screen` → `bookmark_provider` + `highlight_provider`

## Security Architecture

### Encryption Layers:
1. **File Encryption** — AES-256 encryption for PDF files
2. **Secure Storage** — FlutterSecureStorage for keys/tokens
3. **Biometric Auth** — Local authentication for app access
4. **App Lock** — PIN/biometric app lock
5. **Secure Folders** — Encrypted folder containers

### Key Security Services:
- `EncryptionService` — Core encryption/decryption
- `BiometricAuthService` — Biometric authentication
- `AppLockService` — App lock management
- `SecureFolderProvider` — Secure folder operations

## File Management Architecture

### Core Services:
- `FileService` — Low-level file operations
- `PermissionService` — Storage permission handling
- `IntentHandler` — Android intent handling (file open)
- `ScannedPathsProvider` — File scanning/caching

### State Management:
- `FileOperationsProvider` — File CRUD state
- `SortSearchProvider` — Sorting/filtering state
- `FavoritesProvider` — Favorites management
- `RecentFilesProvider` — Recent files tracking

## PDF Viewer Features

### Core Features:
- PDF rendering (pdfrx package)
- Page navigation
- Thumbnail grid
- Bounded PDF text search through `SearchProvider`
- Large-document and image-only search gates
- Search match navigation and active-page geometry loading
- Bookmark panel
- Highlight panel

### Advanced Features:
- Continuous scroll mode
- Dark reading mode
- Page number display
- Zoom controls
- Search overlay isolated from the viewer layout
- Secure remembered passwords for standard protected PDFs

## Testing Strategy

### Test Coverage Areas:
1. **Unit Tests** — Services, providers, models
2. **Widget Tests** — UI components
3. **Integration Tests** — Full workflows
4. **Security Tests** — Encryption, authentication

### Key Test Files:
- `encryption_service_test.dart`
- `bookmark_service_test.dart`
- `highlight_service_test.dart`
- `file_service_test.dart`
- `pdf_password_storage_test.dart`
- `pdf_password_dialog_test.dart`
- `viewer_integration_test.dart`

## Known Issues & Technical Debt

### Architecture Issues:
1. **Fragmented Communities** — 125 communities (many duplicates) suggests:
   - Over-fragmented module boundaries
   - Potential for module consolidation
   - Weak cohesion in some areas

2. **Isolated Nodes** — 1,383 nodes with ≤1 connection:
   - Missing documentation
   - Potential dead code
   - Unused dependencies

3. **High Centrality Nodes** — `home_screen`, `main`, `viewer_screen`:
   - Potential bottleneck points
   - High coupling to multiple modules
   - Consider refactoring for better separation

### Recommended Improvements:
1. **Consolidate Similar Modules** — Merge duplicate communities
2. **Reduce God Node Complexity** — Break down highly connected nodes
3. **Improve Documentation** — Address isolated nodes
4. **Strengthen Cohesion** — Improve low-cohesion communities

## Module Relationships

```
                    ┌─────────────────┐
                    │   App Entry     │
                    │     (main)      │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   Home Screen   │
                    │ (file browser)  │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
┌───────▼───────┐    ┌───────▼───────┐    ┌───────▼───────┐
│ File Ops      │    │ Tags          │    │ Settings      │
│ Provider      │    │ Provider      │    │ Provider      │
└───────┬───────┘    └───────────────┘    └───────────────┘
        │
┌───────▼───────┐
│ PDF Viewer    │
│ Screen        │
└───────┬───────┘
        │
┌───────▼───────┐    ┌───────────────┐
│ Bookmarks     │    │ Highlights    │
│ Provider      │    │ Provider      │
└───────────────┘    └───────────────┘
```

## Technology Stack

- **Framework:** Flutter (Dart)
- **State Management:** Provider pattern
- **PDF Rendering:** pdfrx package
- **Encryption:** AES-256 (dart:crypto)
- **Secure Storage:** FlutterSecureStorage
- **Biometrics:** local_auth package
- **Storage:** SharedPreferences, file system
- **HTTP:** http package (for updates)
- **Testing:** flutter_test, mockito

## File Structure Overview

```
lib/
├── core/
│   ├── models/          # Data models (PdfFile, etc.)
│   └── theme/           # App theming
├── features/
│   ├── bookmarks/       # Bookmark feature
│   ├── encryption/      # Encryption services
│   ├── file_management/ # File operations
│   ├── highlights/      # Highlight feature
│   ├── security/        # Security services
│   ├── settings/        # Settings & profile
│   ├── tags/            # Tag feature
│   ├── updates/         # App updates
│   └── viewer/          # PDF viewer
├── providers/           # Global providers
└── main.dart            # App entry point
```

## Quick Reference

### Key Entry Points:
- `main.dart` — App initialization
- `home_screen.dart` — File browser
- `viewer_screen.dart` — PDF viewer

### Key Providers:
- `app_state.dart` — Global state
- `file_operations_provider.dart` — File operations
- `settings_provider.dart` — Settings
- `bookmark_provider.dart` — Bookmarks
- `highlight_provider.dart` — Highlights
- `search_provider.dart` — Bounded PDF search state and matching

### Key Services:
- `encryption_service.dart` — Encryption
- `file_service.dart` — File operations
- `bookmark_service.dart` — Bookmarks
- `highlight_service.dart` — Highlights
- `settings_service.dart` — Settings

---

*This knowledge map is based on static analysis of the FeyaPDF codebase. For interactive exploration, open `graphify-out/graph.html` in a browser.*
