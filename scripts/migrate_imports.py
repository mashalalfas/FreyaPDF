#!/usr/bin/env python3
"""
Migrate relative imports in FeyaPDF lib/ to package:feya_pdf/... imports.

Walks every .dart file under lib/, parses each `import '...';` line, resolves
the relative target against the file's current location, and rewrites the
import to a package import rooted at the new location.

Also rewrites package: imports in test/ when they start with package:feya_pdf/.
"""

from __future__ import annotations
import os
import re
import sys
from pathlib import Path

ROOT = Path("/home/max/Development/FeyaPDF")
LIB = ROOT / "lib"
TEST = ROOT / "test"

# Mapping of OLD lib-relative path segments to NEW package paths.
# E.g. the string "../models/pdf_file.dart" anywhere → the package path.
OLD_TO_NEW = {
    # core
    "../models/pdf_file.dart": "package:feya_pdf/core/models/pdf_file.dart",
    # bookmarks
    "../models/bookmark.dart": "package:feya_pdf/features/bookmarks/bookmark.dart",
    "bookmark.dart": "package:feya_pdf/features/bookmarks/bookmark.dart",
    "../services/bookmark_service.dart": "package:feya_pdf/features/bookmarks/bookmark_service.dart",
    "bookmark_service.dart": "package:feya_pdf/features/bookmarks/bookmark_service.dart",
    "../providers/bookmark_provider.dart": "package:feya_pdf/features/bookmarks/bookmark_provider.dart",
    "bookmark_provider.dart": "package:feya_pdf/features/bookmarks/bookmark_provider.dart",
    "../widgets/bookmarks_panel.dart": "package:feya_pdf/features/bookmarks/widgets/bookmarks_panel.dart",
    # highlights
    "../models/highlight.dart": "package:feya_pdf/features/highlights/highlight.dart",
    "highlight.dart": "package:feya_pdf/features/highlights/highlight.dart",
    "../services/highlight_service.dart": "package:feya_pdf/features/highlights/highlight_service.dart",
    "highlight_service.dart": "package:feya_pdf/features/highlights/highlight_service.dart",
    "../providers/highlight_provider.dart": "package:feya_pdf/features/highlights/highlight_provider.dart",
    "highlight_provider.dart": "package:feya_pdf/features/highlights/highlight_provider.dart",
    "../widgets/highlights_panel.dart": "package:feya_pdf/features/highlights/widgets/highlights_panel.dart",
    # tags
    "../models/tag.dart": "package:feya_pdf/features/tags/tag.dart",
    "tag.dart": "package:feya_pdf/features/tags/tag.dart",
    "../services/tag_service.dart": "package:feya_pdf/features/tags/tag_service.dart",
    "tag_service.dart": "package:feya_pdf/features/tags/tag_service.dart",
    "../providers/tag_provider.dart": "package:feya_pdf/features/tags/tag_provider.dart",
    "tag_provider.dart": "package:feya_pdf/features/tags/tag_provider.dart",
    "../widgets/tag_chip.dart": "package:feya_pdf/features/tags/widgets/tag_chip.dart",
    "tag_chip.dart": "package:feya_pdf/features/tags/widgets/tag_chip.dart",
    "../widgets/tag_picker_dialog.dart": "package:feya_pdf/features/tags/widgets/tag_picker_dialog.dart",
    # settings
    "../models/user_profile.dart": "package:feya_pdf/features/settings/user_profile.dart",
    "user_profile.dart": "package:feya_pdf/features/settings/user_profile.dart",
    "../services/settings_service.dart": "package:feya_pdf/features/settings/settings_service.dart",
    "settings_service.dart": "package:feya_pdf/features/settings/settings_service.dart",
    "../providers/settings_provider.dart": "package:feya_pdf/features/settings/settings_provider.dart",
    "settings_provider.dart": "package:feya_pdf/features/settings/settings_provider.dart",
    "../services/backup_service.dart": "package:feya_pdf/features/settings/backup_service.dart",
    "backup_service.dart": "package:feya_pdf/features/settings/backup_service.dart",
    "../providers/backup_provider.dart": "package:feya_pdf/features/settings/backup_provider.dart",
    "backup_provider.dart": "package:feya_pdf/features/settings/backup_provider.dart",
    "../screens/settings_screen.dart": "package:feya_pdf/features/settings/settings_screen.dart",
    # encryption
    "../services/encryption_service.dart": "package:feya_pdf/features/encryption/encryption_service.dart",
    "encryption_service.dart": "package:feya_pdf/features/encryption/encryption_service.dart",
    "../services/passphrase_strength.dart": "package:feya_pdf/features/encryption/passphrase_strength.dart",
    "../providers/encryption_provider.dart": "package:feya_pdf/features/encryption/encryption_provider.dart",
    "../widgets/passphrase_dialog.dart": "package:feya_pdf/features/encryption/widgets/passphrase_dialog.dart",
    "../widgets/encryption_badge.dart": "package:feya_pdf/features/encryption/widgets/encryption_badge.dart",
    # viewer
    "../services/page_navigation.dart": "package:feya_pdf/features/viewer/page_navigation.dart",
    "../providers/search_provider.dart": "package:feya_pdf/features/viewer/providers/search_provider.dart",
    "../widgets/search_bar.dart": "package:feya_pdf/features/viewer/widgets/search_bar.dart",
    "../widgets/thumbnail_grid.dart": "package:feya_pdf/features/viewer/widgets/thumbnail_grid.dart",
    "../screens/viewer_screen.dart": "package:feya_pdf/features/viewer/viewer_screen.dart",
    # file_management
    "../services/file_service.dart": "package:feya_pdf/features/file_management/file_service.dart",
    "../services/permission_service.dart": "package:feya_pdf/features/file_management/permission_service.dart",
    "../services/intent_handler.dart": "package:feya_pdf/features/file_management/intent_handler.dart",
    "../providers/app_state.dart": "package:feya_pdf/features/file_management/app_state.dart",
    "app_state.dart": "package:feya_pdf/features/file_management/app_state.dart",
    "../providers/file_operations_provider.dart": "package:feya_pdf/features/file_management/file_operations_provider.dart",
    "file_operations_provider.dart": "package:feya_pdf/features/file_management/file_operations_provider.dart",
    "../providers/recent_files_provider.dart": "package:feya_pdf/features/file_management/recent_files_provider.dart",
    "recent_files_provider.dart": "package:feya_pdf/features/file_management/recent_files_provider.dart",
    "../providers/favorites_provider.dart": "package:feya_pdf/features/file_management/favorites_provider.dart",
    "favorites_provider.dart": "package:feya_pdf/features/file_management/favorites_provider.dart",
    "../providers/scanned_paths_provider.dart": "package:feya_pdf/features/file_management/scanned_paths_provider.dart",
    "scanned_paths_provider.dart": "package:feya_pdf/features/file_management/scanned_paths_provider.dart",
    "../providers/selection_provider.dart": "package:feya_pdf/features/file_management/selection_provider.dart",
    "selection_provider.dart": "package:feya_pdf/features/file_management/selection_provider.dart",
    "../providers/sort_search_provider.dart": "package:feya_pdf/features/file_management/sort_search_provider.dart",
    "sort_search_provider.dart": "package:feya_pdf/features/file_management/sort_search_provider.dart",
    "../widgets/file_list_tile.dart": "package:feya_pdf/features/file_management/widgets/file_list_tile.dart",
    "../screens/home_screen.dart": "package:feya_pdf/features/file_management/home_screen.dart",
    # security
    "../models/secure_folder.dart": "package:feya_pdf/features/security/secure_folder.dart",
    "secure_folder.dart": "package:feya_pdf/features/security/secure_folder.dart",
    "../services/app_lock_service.dart": "package:feya_pdf/features/security/app_lock_service.dart",
    "../services/biometric_auth_service.dart": "package:feya_pdf/features/security/biometric_auth_service.dart",
    "../services/secure_folder_service.dart": "package:feya_pdf/features/security/secure_folder_service.dart",
    "../providers/secure_folder_provider.dart": "package:feya_pdf/features/security/secure_folder_provider.dart",
    "../widgets/app_lock_screen.dart": "package:feya_pdf/features/security/widgets/app_lock_screen.dart",
    "../widgets/biometric_unlock_dialog.dart": "package:feya_pdf/features/security/widgets/biometric_unlock_dialog.dart",
    "../widgets/secure_folder_card.dart": "package:feya_pdf/features/security/widgets/secure_folder_card.dart",
    "../widgets/secure_folder_import_dialog.dart": "package:feya_pdf/features/security/widgets/secure_folder_import_dialog.dart",
    # root lib files (relative-from-root)
    "providers/app_state.dart": "package:feya_pdf/features/file_management/app_state.dart",
    "providers/file_operations_provider.dart": "package:feya_pdf/features/file_management/file_operations_provider.dart",
    "providers/recent_files_provider.dart": "package:feya_pdf/features/file_management/recent_files_provider.dart",
    "providers/favorites_provider.dart": "package:feya_pdf/features/file_management/favorites_provider.dart",
    "providers/scanned_paths_provider.dart": "package:feya_pdf/features/file_management/scanned_paths_provider.dart",
    "providers/selection_provider.dart": "package:feya_pdf/features/file_management/selection_provider.dart",
    "providers/sort_search_provider.dart": "package:feya_pdf/features/file_management/sort_search_provider.dart",
    "providers/encryption_provider.dart": "package:feya_pdf/features/encryption/encryption_provider.dart",
    "providers/tag_provider.dart": "package:feya_pdf/features/tags/tag_provider.dart",
    "providers/settings_provider.dart": "package:feya_pdf/features/settings/settings_provider.dart",
    "providers/bookmark_provider.dart": "package:feya_pdf/features/bookmarks/bookmark_provider.dart",
    "providers/highlight_provider.dart": "package:feya_pdf/features/highlights/highlight_provider.dart",
    "providers/backup_provider.dart": "package:feya_pdf/features/settings/backup_provider.dart",
    "providers/secure_folder_provider.dart": "package:feya_pdf/features/security/secure_folder_provider.dart",
    "services/file_service.dart": "package:feya_pdf/features/file_management/file_service.dart",
    "services/permission_service.dart": "package:feya_pdf/features/file_management/permission_service.dart",
    "services/intent_handler.dart": "package:feya_pdf/features/file_management/intent_handler.dart",
    "services/bookmark_service.dart": "package:feya_pdf/features/bookmarks/bookmark_service.dart",
    "services/highlight_service.dart": "package:feya_pdf/features/highlights/highlight_service.dart",
    "services/tag_service.dart": "package:feya_pdf/features/tags/tag_service.dart",
    "services/settings_service.dart": "package:feya_pdf/features/settings/settings_service.dart",
    "services/backup_service.dart": "package:feya_pdf/features/settings/backup_service.dart",
    "services/encryption_service.dart": "package:feya_pdf/features/encryption/encryption_service.dart",
    "screens/home_screen.dart": "package:feya_pdf/features/file_management/home_screen.dart",
    "screens/settings_screen.dart": "package:feya_pdf/features/settings/settings_screen.dart",
    "screens/tags_screen.dart": "package:feya_pdf/features/tags/tags_screen.dart",
    "screens/viewer_screen.dart": "package:feya_pdf/features/viewer/viewer_screen.dart",
    "widgets/app_lock_screen.dart": "package:feya_pdf/features/security/widgets/app_lock_screen.dart",
    # Same-name bare imports inside home_screen.dart (same directory prefix
    # before refactor, different feature after refactor).
    "viewer_screen.dart": "package:feya_pdf/features/viewer/viewer_screen.dart",
    "settings_screen.dart": "package:feya_pdf/features/settings/settings_screen.dart",
    "tags_screen.dart": "package:feya_pdf/features/tags/tags_screen.dart",
    "home_screen.dart": "package:feya_pdf/features/file_management/home_screen.dart",
    "theme.dart": "package:feya_pdf/theme.dart",
}

# Test files use `package:feya_pdf/<old-path>` style (no leading `lib/`).
# Map the old package-path to its new location.
OLD_PKG_PATH_TO_NEW_PKG = {
    "package:feya_pdf/models/pdf_file.dart": "package:feya_pdf/core/models/pdf_file.dart",
    "package:feya_pdf/models/bookmark.dart": "package:feya_pdf/features/bookmarks/bookmark.dart",
    "package:feya_pdf/models/highlight.dart": "package:feya_pdf/features/highlights/highlight.dart",
    "package:feya_pdf/models/tag.dart": "package:feya_pdf/features/tags/tag.dart",
    "package:feya_pdf/models/user_profile.dart": "package:feya_pdf/features/settings/user_profile.dart",
    "package:feya_pdf/models/secure_folder.dart": "package:feya_pdf/features/security/secure_folder.dart",
    "package:feya_pdf/services/file_service.dart": "package:feya_pdf/features/file_management/file_service.dart",
    "package:feya_pdf/services/permission_service.dart": "package:feya_pdf/features/file_management/permission_service.dart",
    "package:feya_pdf/services/intent_handler.dart": "package:feya_pdf/features/file_management/intent_handler.dart",
    "package:feya_pdf/services/bookmark_service.dart": "package:feya_pdf/features/bookmarks/bookmark_service.dart",
    "package:feya_pdf/services/highlight_service.dart": "package:feya_pdf/features/highlights/highlight_service.dart",
    "package:feya_pdf/services/tag_service.dart": "package:feya_pdf/features/tags/tag_service.dart",
    "package:feya_pdf/services/settings_service.dart": "package:feya_pdf/features/settings/settings_service.dart",
    "package:feya_pdf/services/backup_service.dart": "package:feya_pdf/features/settings/backup_service.dart",
    "package:feya_pdf/services/encryption_service.dart": "package:feya_pdf/features/encryption/encryption_service.dart",
    "package:feya_pdf/services/passphrase_strength.dart": "package:feya_pdf/features/encryption/passphrase_strength.dart",
    "package:feya_pdf/services/app_lock_service.dart": "package:feya_pdf/features/security/app_lock_service.dart",
    "package:feya_pdf/services/biometric_auth_service.dart": "package:feya_pdf/features/security/biometric_auth_service.dart",
    "package:feya_pdf/services/secure_folder_service.dart": "package:feya_pdf/features/security/secure_folder_service.dart",
    "package:feya_pdf/services/page_navigation.dart": "package:feya_pdf/features/viewer/page_navigation.dart",
    "package:feya_pdf/providers/app_state.dart": "package:feya_pdf/features/file_management/app_state.dart",
    "package:feya_pdf/providers/file_operations_provider.dart": "package:feya_pdf/features/file_management/file_operations_provider.dart",
    "package:feya_pdf/providers/recent_files_provider.dart": "package:feya_pdf/features/file_management/recent_files_provider.dart",
    "package:feya_pdf/providers/favorites_provider.dart": "package:feya_pdf/features/file_management/favorites_provider.dart",
    "package:feya_pdf/providers/scanned_paths_provider.dart": "package:feya_pdf/features/file_management/scanned_paths_provider.dart",
    "package:feya_pdf/providers/selection_provider.dart": "package:feya_pdf/features/file_management/selection_provider.dart",
    "package:feya_pdf/providers/sort_search_provider.dart": "package:feya_pdf/features/file_management/sort_search_provider.dart",
    "package:feya_pdf/providers/bookmark_provider.dart": "package:feya_pdf/features/bookmarks/bookmark_provider.dart",
    "package:feya_pdf/providers/highlight_provider.dart": "package:feya_pdf/features/highlights/highlight_provider.dart",
    "package:feya_pdf/providers/tag_provider.dart": "package:feya_pdf/features/tags/tag_provider.dart",
    "package:feya_pdf/providers/encryption_provider.dart": "package:feya_pdf/features/encryption/encryption_provider.dart",
    "package:feya_pdf/providers/settings_provider.dart": "package:feya_pdf/features/settings/settings_provider.dart",
    "package:feya_pdf/providers/backup_provider.dart": "package:feya_pdf/features/settings/backup_provider.dart",
    "package:feya_pdf/providers/secure_folder_provider.dart": "package:feya_pdf/features/security/secure_folder_provider.dart",
    "package:feya_pdf/providers/search_provider.dart": "package:feya_pdf/features/viewer/providers/search_provider.dart",
    "package:feya_pdf/screens/home_screen.dart": "package:feya_pdf/features/file_management/home_screen.dart",
    "package:feya_pdf/screens/settings_screen.dart": "package:feya_pdf/features/settings/settings_screen.dart",
    "package:feya_pdf/screens/tags_screen.dart": "package:feya_pdf/features/tags/tags_screen.dart",
    "package:feya_pdf/screens/viewer_screen.dart": "package:feya_pdf/features/viewer/viewer_screen.dart",
    "package:feya_pdf/widgets/file_list_tile.dart": "package:feya_pdf/features/file_management/widgets/file_list_tile.dart",
    "package:feya_pdf/widgets/tag_chip.dart": "package:feya_pdf/features/tags/widgets/tag_chip.dart",
    "package:feya_pdf/widgets/tag_picker_dialog.dart": "package:feya_pdf/features/tags/widgets/tag_picker_dialog.dart",
    "package:feya_pdf/widgets/encryption_badge.dart": "package:feya_pdf/features/encryption/widgets/encryption_badge.dart",
    "package:feya_pdf/widgets/passphrase_dialog.dart": "package:feya_pdf/features/encryption/widgets/passphrase_dialog.dart",
    "package:feya_pdf/widgets/app_lock_screen.dart": "package:feya_pdf/features/security/widgets/app_lock_screen.dart",
    "package:feya_pdf/widgets/biometric_unlock_dialog.dart": "package:feya_pdf/features/security/widgets/biometric_unlock_dialog.dart",
    "package:feya_pdf/widgets/secure_folder_card.dart": "package:feya_pdf/features/security/widgets/secure_folder_card.dart",
    "package:feya_pdf/widgets/secure_folder_import_dialog.dart": "package:feya_pdf/features/security/widgets/secure_folder_import_dialog.dart",
    "package:feya_pdf/widgets/bookmarks_panel.dart": "package:feya_pdf/features/bookmarks/widgets/bookmarks_panel.dart",
    "package:feya_pdf/widgets/highlights_panel.dart": "package:feya_pdf/features/highlights/widgets/highlights_panel.dart",
    "package:feya_pdf/widgets/search_bar.dart": "package:feya_pdf/features/viewer/widgets/search_bar.dart",
    "package:feya_pdf/widgets/thumbnail_grid.dart": "package:feya_pdf/features/viewer/widgets/thumbnail_grid.dart",
}

RELATIVE_IMPORT_RE = re.compile(r"^(?P<prefix>import\s+['\"])(?P<path>[^'\"]+)(?P<suffix>['\"];?)\s*$")


def migrate_lib_file(path: Path) -> tuple[int, int]:
    """Rewrite `import '...';` lines in a lib/.dart file when the path is a
    relative or same-package reference that has moved under the new layout.

    Only relative imports (`./foo.dart`, `../foo/bar.dart`, `foo.dart`) are
    touched. `dart:` and `package:` (non-feya_pdf) imports are left alone.
    Package imports under `package:feya_pdf/` that no longer exist are left
    alone (the test rewrite step owns those).
    """
    text = path.read_text()
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    changed = 0
    total = 0
    for line in lines:
        m = RELATIVE_IMPORT_RE.match(line.rstrip("\n"))
        if not m:
            out.append(line)
            continue
        total += 1
        old_path = m.group("path")
        # Skip stdlib and 3rd-party package imports — they're correct as-is.
        if old_path.startswith("dart:") or old_path.startswith("package:"):
            out.append(line)
            continue
        new_path = OLD_TO_NEW.get(old_path)
        if new_path is None:
            # Fall back to file-system resolution ONLY when the target file
            # actually exists at the resolved path. (Avoids wrong
            # feature-folder matches for bare-name imports like
            # `import 'viewer_screen.dart';` from inside
            # `lib/features/file_management/home_screen.dart`.)
            resolved = (path.parent / old_path).resolve()
            try:
                rel = resolved.relative_to(LIB.resolve())
            except ValueError:
                out.append(line)
                continue
            if not resolved.exists():
                print(
                    f"WARN bare import without OLD_TO_NEW entry: "
                    f"{path.relative_to(ROOT)}: {old_path}",
                    file=sys.stderr,
                )
                out.append(line)
                continue
            new_path = f"package:feya_pdf/{rel.as_posix()}"
        prefix = m.group("prefix")
        suffix = m.group("suffix")
        newline = "\n" if line.endswith("\n") else ""
        new_line = f"{prefix}{new_path}{suffix}{newline}"
        out.append(new_line)
        if new_line != line:
            changed += 1
    if changed:
        path.write_text("".join(out))
    return changed, total


def migrate_test_file(path: Path) -> tuple[int, int]:
    text = path.read_text()
    new_text = text
    changed = 0
    for old_pkg, new_pkg in OLD_PKG_PATH_TO_NEW_PKG.items():
        if old_pkg in new_text:
            new_text = new_text.replace(old_pkg, new_pkg)
            changed += 1
    if changed:
        path.write_text(new_text)
    return changed, 1


def main() -> int:
    total_changed_lib = 0
    total_lib_files = 0
    for p in sorted(LIB.rglob("*.dart")):
        ch, _ = migrate_lib_file(p)
        total_changed_lib += ch
        total_lib_files += 1
    print(f"[lib/] touched {total_changed_lib} imports across {total_lib_files} files")

    total_changed_test = 0
    total_test_files = 0
    for p in sorted(TEST.rglob("*.dart")):
        ch, _ = migrate_test_file(p)
        total_changed_test += ch
        total_test_files += 1
    print(f"[test/] touched {total_changed_test} imports across {total_test_files} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
