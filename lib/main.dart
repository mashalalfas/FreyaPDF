import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:feya_pdf/build_config.dart';
import 'package:feya_pdf/features/file_management/app_state.dart';
import 'package:feya_pdf/features/file_management/favorites_provider.dart';
import 'package:feya_pdf/features/encryption/encryption_provider.dart';
import 'package:feya_pdf/features/security/secure_folder_provider.dart';
import 'package:feya_pdf/features/settings/settings_provider.dart';
import 'package:feya_pdf/features/tags/tag_provider.dart';
import 'package:feya_pdf/features/file_management/sort_search_provider.dart';
import 'package:feya_pdf/features/file_management/recent_files_provider.dart';
import 'package:feya_pdf/features/file_management/scanned_paths_provider.dart';
import 'package:feya_pdf/features/file_management/file_operations_provider.dart';
import 'package:feya_pdf/features/file_management/selection_provider.dart';
import 'package:feya_pdf/features/settings/settings_service.dart';
import 'package:feya_pdf/features/tags/tag_service.dart';
import 'package:feya_pdf/features/file_management/intent_handler.dart';
import 'package:feya_pdf/features/highlights/highlight_service.dart';
import 'package:feya_pdf/features/bookmarks/bookmark_service.dart';
import 'package:feya_pdf/features/highlights/highlight_provider.dart';
import 'package:feya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:feya_pdf/features/settings/backup_provider.dart';
import 'package:feya_pdf/features/settings/backup_service.dart';
import 'package:feya_pdf/features/update/update_provider.dart';
import 'package:feya_pdf/theme.dart';
import 'package:feya_pdf/features/file_management/home_screen.dart';
import 'package:feya_pdf/features/security/widgets/app_lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settingsService = SettingsService(prefs);
  await settingsService.migrateLegacyKeys();

  // Storage migration: rename MelodyPDF → FeyaPDF directories
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
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: const FeyaPdfApp(),
    ),
  );
}

class FeyaPdfApp extends StatefulWidget {
  const FeyaPdfApp({super.key});

  @override
  State<FeyaPdfApp> createState() => _FeyaPdfAppState();
}

class _FeyaPdfAppState extends State<FeyaPdfApp> {
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
      title: 'Feya PDF',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      home: AppLockGate(child: const HomeScreen()),
    );
  }
}

/// Rename old MelodyPDF directories to FeyaPDF so existing users
/// don't lose their saved files after the rebrand.
Future<void> _migrateDirectories() async {
  final appDir = await getApplicationDocumentsDirectory();

  final oldSaveDir = Directory('${appDir.path}/MelodyPDF');
  final newSaveDir = Directory('${appDir.path}/FeyaPDF');
  if (await oldSaveDir.exists() && !await newSaveDir.exists()) {
    try {
      await oldSaveDir.rename(newSaveDir.path);
    } catch (_) {}
  }

  final oldSecureDir = Directory('${appDir.path}/MelodyPDF_Secure');
  final newSecureDir = Directory('${appDir.path}/FeyaPDF_Secure');
  if (await oldSecureDir.exists() && !await newSecureDir.exists()) {
    try {
      await oldSecureDir.rename(newSecureDir.path);
    } catch (_) {}
  }

  final oldExportDir = Directory('${appDir.path}/MelodyPDF_Exports');
  final newExportDir = Directory('${appDir.path}/FeyaPDF_Exports');
  if (await oldExportDir.exists() && !await newExportDir.exists()) {
    try {
      await oldExportDir.rename(newExportDir.path);
    } catch (_) {}
  }
}
