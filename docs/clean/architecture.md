# FeyaPDF — Architecture

Flutter (Dart) PDF reader with provider-based state management and E2E encryption.

## Core modules

| Module | Location | Responsibility |
|---|---|---|
| Viewer & Search | `lib/features/viewer/` | PDF rendering (pdfrx), navigation, search, thumbnails |
| File Management | `lib/features/file_management/` | File browser, SAF access, operations, permissions |
| Security & Encryption | `lib/features/security/`, `lib/features/encryption/` | AES encryption, biometric auth, app lock, secure folders, remembered PDF passwords |
| Bookmarks | `lib/features/bookmarks/` | Per-file bookmark CRUD |
| Highlights | `lib/features/highlights/` | Text + rectangle highlights |
| Tags | `lib/features/tags/` | File tagging |
| Settings & Profile | `lib/features/settings/` | Settings, profile, backup |
| Updates | `lib/features/update/` | GitHub-based update checks |

## God nodes (most connected)

`home_screen` (32) → `main` (31) → `highlight_provider` (29) → `viewer_screen` (28) → `settings_service` (26) → `app_state` (25) → `file_operations_provider` (25) → `BookmarkProvider` (24).

## Data flow

```
User Action → Screen/Widget → Provider → Service → Storage/Encryption
     ↑                                                    ↓
     └────────────────── UI Update ←──────────────────────┘
```

Typical PDF open: `home_screen` → `file_operations_provider` → `file_service` →
`viewer_screen` → `bookmark_provider` + `highlight_provider`.

## Key entry points

- `lib/main.dart` — app initialization, all providers
- `lib/features/file_management/home_screen.dart` — file browser
- `lib/features/viewer/viewer_screen.dart` — PDF viewer
- `lib/features/viewer/providers/search_provider.dart` — bounded PDF search

## Tech stack

Flutter / Provider / pdfrx / AES-256-GCM + PBKDF2 / FlutterSecureStorage / local_auth /
SharedPreferences / http (updates).

## Current graph (graphify, 2026-08-09)

2,283 nodes · 3,570 edges · 125 communities (AST extraction; semantic extraction requires an LLM API key).
