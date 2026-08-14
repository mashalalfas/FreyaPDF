// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/build_config.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/file_management/favorites_provider.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';

import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/tags/tag_provider.dart';
import 'package:freya_pdf/features/file_management/sort_search_provider.dart';
import 'package:freya_pdf/features/file_management/recent_files_provider.dart';
import 'package:freya_pdf/features/file_management/scanned_paths_provider.dart';
import 'package:freya_pdf/features/file_management/file_operations_provider.dart';
import 'package:freya_pdf/features/file_management/selection_provider.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';
import 'package:freya_pdf/features/tags/tag_service.dart';
import 'package:freya_pdf/features/file_management/intent_handler.dart';
import 'package:freya_pdf/features/highlights/highlight_service.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_service.dart';
import 'package:freya_pdf/features/highlights/highlight_provider.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:freya_pdf/features/viewer/providers/search_provider.dart';
import 'package:freya_pdf/features/settings/backup_provider.dart';
import 'package:freya_pdf/features/settings/backup_service.dart';
import 'package:freya_pdf/features/update/update_provider.dart';
import 'package:freya_pdf/theme.dart';
import 'package:freya_pdf/features/file_management/home_screen.dart';
import 'package:freya_pdf/features/security/widgets/app_lock_screen.dart';
import 'package:freya_pdf/features/security/widgets/root_security_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settingsService = SettingsService(prefs);
  await settingsService.migrateLegacyKeys();

  // Storage migration: rename MelodyPDF → FreyaPDF directories
  await _migrateDirectories();
  final tagService = TagService(prefs);
  final highlightService = HighlightService(prefs);
  final bookmarkService = BookmarkService(prefs);
  final backupService = BackupService(
    settingsService: settingsService,
    tagService: tagService,
    highlightService: highlightService,
    bookmarkService: bookmarkService,
  );
  IntentHandler.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EncryptionProvider()),
        ChangeNotifierProvider(create: (_) => SecureFolderProvider()),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(settingsService),
        ),
        ChangeNotifierProvider(
          create: (_) => FavoritesProvider(settingsService),
        ),
        ChangeNotifierProvider(create: (_) => TagProvider(tagService)),
        ChangeNotifierProvider(create: (_) => SortSearchProvider()),
        ChangeNotifierProvider(create: (_) => RecentFilesProvider()),
        ChangeNotifierProvider(create: (_) => ScannedPathsProvider()),
        ChangeNotifierProvider(create: (_) => FileOperationsProvider()),
        ChangeNotifierProvider(
          create: (_) => HighlightProvider(highlightService),
        ),
        ChangeNotifierProvider(
          create: (_) => BookmarkProvider(bookmarkService),
        ),
        ChangeNotifierProvider(create: (_) => BackupProvider(backupService)),
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => SelectionProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: const FreyaPdfApp(),
    ),
  );
}

class FreyaPdfApp extends StatefulWidget {
  const FreyaPdfApp({super.key});

  @override
  State<FreyaPdfApp> createState() => _FreyaPdfAppState();
}

class _FreyaPdfAppState extends State<FreyaPdfApp> {
  bool _wired = false;

  @override
  void initState() {
    super.initState();
    // Wire cross-provider dependencies once, after the first frame so
    // Provider context is fully available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_wired && mounted) {
        _wired = true;

        // Initialize update provider and fire a silent background check.
        final update = context.read<UpdateProvider>();
        update.init();
        if (!BuildConfig.isPlayStoreBuild) {
          update.checkForUpdate(silent: true);
        }
        final appState = context.read<AppState>();
        final sortSearch = context.read<SortSearchProvider>();
        final paths = context.read<ScannedPathsProvider>();
        final fileOps = context.read<FileOperationsProvider>();

        appState.attachSortSearch(sortSearch);
        appState.attachScannedPaths(paths);

        fileOps.attachEncryption(context.read<EncryptionProvider>());

        context
            .read<SecureFolderProvider>()
            .attachEncryption(context.read<EncryptionProvider>());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp(
      title: 'Freya PDF',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: RootSecurityGate(
        child: AppLockGate(child: const HomeScreen()),
      ),
    );
  }
}

/// Rename old storage directories to the current FreyaPDF layout so existing
/// users don't lose their saved files across rebrands.
///
/// Chain: MelodyPDF → FeyaPDF → FreyaPDF. Each step only runs if the source
/// exists and the destination doesn't, so it's idempotent across upgrades.
Future<void> _migrateDirectories() async {
  final appDir = await getApplicationDocumentsDirectory();

  await _migrateDir(
    '${appDir.path}/MelodyPDF',
    '${appDir.path}/FeyaPDF',
  );
  await _migrateDir(
    '${appDir.path}/FeyaPDF',
    '${appDir.path}/FreyaPDF',
  );

  await _migrateDir(
    '${appDir.path}/MelodyPDF_Secure',
    '${appDir.path}/FeyaPDF_Secure',
  );
  await _migrateDir(
    '${appDir.path}/FeyaPDF_Secure',
    '${appDir.path}/FreyaPDF_Secure',
  );

  await _migrateDir(
    '${appDir.path}/MelodyPDF_Exports',
    '${appDir.path}/FeyaPDF_Exports',
  );
  await _migrateDir(
    '${appDir.path}/FeyaPDF_Exports',
    '${appDir.path}/FreyaPDF_Exports',
  );
}

/// Rename [oldPath] to [newPath] if it exists and the destination is free.
Future<void> _migrateDir(String oldPath, String newPath) async {
  final oldDir = Directory(oldPath);
  final newDir = Directory(newPath);
  if (await oldDir.exists() && !await newDir.exists()) {
    try {
      await oldDir.rename(newDir.path);
    } catch (_) {}
  }
}
