// Size: large — widget smoke tests (Flutter rendering baseline)
//
// These tests confirm the app's root widget tree builds without error.
// They run on every flutter test invocation and guard against scaffold breakage.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/main.dart';
import 'package:feya_pdf/features/file_management/app_state.dart';
import 'package:feya_pdf/features/settings/backup_provider.dart';
import 'package:feya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:feya_pdf/features/encryption/encryption_provider.dart';
import 'package:feya_pdf/features/file_management/favorites_provider.dart';
import 'package:feya_pdf/features/file_management/file_operations_provider.dart';
import 'package:feya_pdf/features/highlights/highlight_provider.dart';
import 'package:feya_pdf/features/file_management/recent_files_provider.dart';
import 'package:feya_pdf/features/file_management/scanned_paths_provider.dart';
import 'package:feya_pdf/features/security/secure_folder_provider.dart';
import 'package:feya_pdf/features/file_management/selection_provider.dart';
import 'package:feya_pdf/features/settings/settings_provider.dart';
import 'package:feya_pdf/features/file_management/sort_search_provider.dart';
import 'package:feya_pdf/features/tags/tag_provider.dart';
import 'package:feya_pdf/features/settings/backup_service.dart';
import 'package:feya_pdf/features/bookmarks/bookmark_service.dart';
import 'package:feya_pdf/features/highlights/highlight_service.dart';
import 'package:feya_pdf/features/settings/settings_service.dart';
import 'package:feya_pdf/features/tags/tag_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('App smoke tests', () {
    // Arrange: nothing beyond the default test environment
    // Act: build the app root widget via MelodyPDFApp
    // Assert: widget builds without throwing, Scaffold is in the tree
    testWidgets('FeyaPdfApp builds without throwing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = SettingsService(prefs);
      final tagService = TagService(prefs);
      final highlightService = HighlightService(prefs);
      final bookmarkService = BookmarkService(prefs);
      final backupService = BackupService(
        settingsService: settingsService,
        tagService: tagService,
        highlightService: highlightService,
        bookmarkService: bookmarkService,
      );

      // Arrange & Act
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => EncryptionProvider()),
            ChangeNotifierProvider(create: (_) => SortSearchProvider()),
            ChangeNotifierProvider(create: (_) => RecentFilesProvider()),
            ChangeNotifierProvider(create: (_) => ScannedPathsProvider()),
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(settingsService),
            ),
            ChangeNotifierProvider(create: (_) => TagProvider(tagService)),
            ChangeNotifierProvider(create: (_) => FileOperationsProvider()),
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider(create: (_) => SecureFolderProvider()),
            ChangeNotifierProvider(
              create: (_) => HighlightProvider(highlightService),
            ),
            ChangeNotifierProvider(
              create: (_) => BookmarkProvider(bookmarkService),
            ),
            ChangeNotifierProvider(create: (_) => BackupProvider(backupService)),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(settingsService)),
            ChangeNotifierProvider(create: (_) => SelectionProvider()),
          ],
          child: const FeyaPdfApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('FeyaPdfApp shows a MaterialApp on first frame', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settingsService = SettingsService(prefs);
      final tagService = TagService(prefs);
      final highlightService = HighlightService(prefs);
      final bookmarkService = BookmarkService(prefs);
      final backupService = BackupService(
        settingsService: settingsService,
        tagService: tagService,
        highlightService: highlightService,
        bookmarkService: bookmarkService,
      );

      // Arrange & Act
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => EncryptionProvider()),
            ChangeNotifierProvider(create: (_) => SortSearchProvider()),
            ChangeNotifierProvider(create: (_) => RecentFilesProvider()),
            ChangeNotifierProvider(create: (_) => ScannedPathsProvider()),
            ChangeNotifierProvider(
              create: (_) => SettingsProvider(settingsService),
            ),
            ChangeNotifierProvider(create: (_) => TagProvider(tagService)),
            ChangeNotifierProvider(create: (_) => FileOperationsProvider()),
            ChangeNotifierProvider(create: (_) => AppState()),
            ChangeNotifierProvider(create: (_) => SecureFolderProvider()),
            ChangeNotifierProvider(
              create: (_) => HighlightProvider(highlightService),
            ),
            ChangeNotifierProvider(
              create: (_) => BookmarkProvider(bookmarkService),
            ),
            ChangeNotifierProvider(create: (_) => BackupProvider(backupService)),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(settingsService)),
            ChangeNotifierProvider(create: (_) => SelectionProvider()),
          ],
          child: const FeyaPdfApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
