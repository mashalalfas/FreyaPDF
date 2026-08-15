// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:freya_pdf/features/bookmarks/bookmark.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/file_management/favorites_provider.dart';
import 'package:freya_pdf/features/tags/tag_provider.dart';
import 'package:freya_pdf/features/file_management/sort_search_provider.dart';
import 'package:freya_pdf/features/file_management/selection_provider.dart';
import 'package:freya_pdf/features/file_management/file_operations_provider.dart';
import 'package:freya_pdf/features/file_management/recent_files_provider.dart';
import 'package:freya_pdf/features/file_management/scanned_paths_provider.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/core/widgets/freya_snack_bar.dart';
import 'package:freya_pdf/core/widgets/empty_state.dart';
import 'package:freya_pdf/core/widgets/fab_speed_dial.dart';
import 'package:freya_pdf/features/file_management/pdf_import_service.dart';
import 'package:freya_pdf/features/file_management/widgets/file_list_tile.dart';
import 'package:freya_pdf/features/tags/widgets/tag_chip.dart';
import 'package:freya_pdf/features/tags/widgets/tag_picker_dialog.dart';
import 'package:freya_pdf/features/encryption/widgets/encrypting_progress_dialog.dart';
import 'package:freya_pdf/features/encryption/widgets/passphrase_dialog.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_card.dart';
import 'package:freya_pdf/features/file_management/widgets/delete_original_dialog.dart';
import 'package:freya_pdf/features/file_management/permission_service.dart';
import 'package:freya_pdf/features/file_management/intent_handler.dart';
import 'package:freya_pdf/features/security/secure_folder_service.dart';
import 'package:freya_pdf/features/viewer/viewer_screen.dart';
import 'package:freya_pdf/features/settings/settings_screen.dart';
import 'package:freya_pdf/features/tags/tags_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  late AnimationController _staggerController;

  // Imports: live inline progress + transient highlight of newly added files.
  final _listScrollController = ScrollController();
  final _importProgress = ValueNotifier<String?>(null);
  final Set<String> _highlightPaths = {};
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final appState = context.read<AppState>();
    final recentProvider = context.read<RecentFilesProvider>();
    final pathsProvider = context.read<ScannedPathsProvider>();

    await recentProvider.loadRecentFiles();
    await pathsProvider.loadScannedPaths();

    final persisted = await pathsProvider.loadPersistedDir();
    bool loaded = false;
    if (persisted != null) {
      if (IntentHandler.isContentUri(persisted)) {
        // Content URI — re-scan via SAF platform channel
        await appState.loadContentUriFiles(persisted);
        loaded = appState.allFiles.isNotEmpty || appState.error != null;
      } else if (await Directory(persisted).exists()) {
        await appState.loadDirectory(persisted);
        loaded = appState.allFiles.isNotEmpty || appState.error != null;
      }
    }
    if (!loaded && pathsProvider.scannedPaths.isNotEmpty) {
      await appState.loadAllDirectories(pathsProvider.scannedPaths);
    }
    if (mounted) {
      _staggerController.forward();
    }

    // Check if app was launched via "Open with" intent
    _checkInitialIntent();

    // Listen for future intents
    IntentHandler.onFileOpened.listen((path) {
      if (mounted) _openFileFromPath(path);
    });
  }

  void _checkInitialIntent() async {
    final path = await IntentHandler.getInitialFilePath();
    if (path != null && mounted) {
      _openFileFromPath(path);
    }
  }

  void _openFileFromPath(String path) {
    final appState = context.read<AppState>();
    // Find file in loaded files, or create a transient one for direct open
    final existing = appState.files.where((f) => f.path == path).toList();
    if (existing.isNotEmpty) {
      _openFile(existing.first);
    } else {
      // File not in scanned list — create a transient PdfFile and open directly
      final file = File(path);
      if (file.existsSync()) {
        final pdfFile = PdfFile(
          path: path,
          name: path.split('/').last,
          sizeBytes: file.lengthSync(),
          modified: file.lastModifiedSync(),
        );
        _openFile(pdfFile);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _staggerController.dispose();
    _listScrollController.dispose();
    _importProgress.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    // Ensure we have MANAGE_EXTERNAL_STORAGE on Android 11+ before picking
    final hasPermission = await PermissionService.hasStoragePermission();
    if (!hasPermission && mounted) {
      final granted = await PermissionService.showPermissionDialog(context);
      if (!granted) return;
    }
    // Re-check after the dialog flow — user may have denied
    final stillNoPermission = !await PermissionService.hasStoragePermission();
    if (stillNoPermission) return;

    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null && mounted) {
      final appState = context.read<AppState>();
      final pathsProvider = context.read<ScannedPathsProvider>();

      if (IntentHandler.isContentUri(result)) {
        // Android SAF content URI — use platform channel to list & copy files
        await pathsProvider.persistAfterPick(result);
        await appState.loadContentUriFiles(result);
      } else {
        // Regular file system path — use dart:io as before
        await pathsProvider.persistAfterPick(result);
        await appState.loadDirectory(result);
        if (appState.error != null && mounted) {
          await _pickFiles();
        }
      }
      _staggerController.reset();
      _staggerController.forward();
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["pdf"],
    );
    if (result != null && mounted) {
      final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
      for (final path in paths) {
        _openFileFromPath(path);
      }
    }
  }

  /// Speed-dial "File" action: pick one-or-more PDFs and import each
  /// individually (copied) into the default library. No auto-open.
  Future<void> _pickImportFiles() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["pdf"],
      allowMultiple: true,
    );
    if (pick == null || pick.files.isEmpty || !mounted) return;

    // Read each selection into memory up-front (SAF URIs stream and can't be
    // seeked, so we hold the full buffer per the import guards).
    // ignore: prefer_final_parameters
    final sources = <PdfImportSource>[];
    var readFailed = false;
    final pending = pick.files;
    for (final f in pending) {
      try {
        // XFile.readAsBytes reads the full stream regardless of whether the
        // picker handed us a real path or a SAF content URI (it copies to
        // cache), so this single call satisfies the in-memory buffer guard.
        final bytes = await f.xFile.readAsBytes();
        sources.add(PdfImportSource(name: f.name, bytes: bytes));
      } catch (e) {
        readFailed = true;
        debugPrint('HomeScreen: failed to read ${f.name}: $e');
      }
    }
    if (sources.isEmpty) {
      if (readFailed && mounted) {
        FreyaSnackBar.show(context, 'Could not read any of the selected files');
      }
      return;
    }

    final cumulative = sources.fold<int>(0, (sum, s) => sum + s.sizeBytes);

    // Preview/confirm cumulative size for large batches before touching disk.
    if (sources.length >= 5) {
      final allowed = await _confirmBatchImport(sources.length, cumulative);
      if (allowed != true || !mounted) return;
    }

    // Fail fast on storage.
    final docsDir = await PdfImportService.docsDirFor();
    final free = await IntentHandler.getFreeBytes(docsDir.path);
    if (PdfImportService.quotaExceeds(free, cumulative)) {
      if (mounted) {
        FreyaSnackBar.show(context, 'Not enough storage to import ${_formatBytes(cumulative)}');
      }
      return;
    }

    final startedImports = sources.length;
    if (sources.length >= 5) {
      _importProgress.value = 'Importing 0 of $startedImports…';
    }

    final results = await PdfImportService.importBatch(
      sources: sources,
      dir: docsDir,
      isCancelled: () => !mounted,
      onProgress: (completed, total) {
        if (total >= 5) {
          _importProgress.value = 'Importing $completed of $total…';
        }
      },
    );
    _importProgress.value = null;
    if (!mounted) return;

    // Refresh so newly imported copies appear in the library.
    // ignore: use_build_context_synchronously
    context.read<AppState>().refresh();

    final imported = results.where((r) => r.isImported).toList();
    final dupes = results.where((r) => r.isDuplicate).toList();
    final failed = results.where((r) => r.status == PdfImportStatus.failed).toList();

    // Scroll to + highlight the newly added files.
    if (imported.isNotEmpty) {
      _highlightImported(imported);
    }

    final parts = <String>[];
    if (imported.isNotEmpty) {
      parts.add('${imported.length} imported');
    }
    if (dupes.isNotEmpty) {
      parts.add('${dupes.length} already in library');
    }
    if (failed.isNotEmpty) {
      final first = failed.first.source.name;
      parts.add('${failed.length} failed: $first');
    }
    final message = parts.isEmpty ? 'Nothing to import' : parts.join(', ');

    final importedPaths = imported
        .map((r) => r.committedPath)
        .whereType<String>()
        .toList();
    FreyaSnackBar.show(
      context,
      message,
      duration: const Duration(seconds: 5),
      action: importedPaths.isNotEmpty ? 'Undo' : null,
      onAction: importedPaths.isNotEmpty
          ? () => _undoImports(docsDir.path, importedPaths)
          : null,
    );
  }

  Future<bool?> _confirmBatchImport(int count, int totalBytes) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Import $count files?'),
        content: Text(
          'This will copy $count PDF files into your library, '
          'totalling ${_formatBytes(totalBytes)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _highlightImported(List<PdfImportResult> imported) {
    _highlightTimer?.cancel();
    _highlightPaths
      ..clear()
      ..addAll(imported.map((r) => r.committedPath).whereType<String>());
    // Focus the first newly added file so the user sees where they landed.
    final files = context.read<AppState>().allFiles;
    final firstPath = imported.first.committedPath;
    if (firstPath != null && _listScrollController.hasClients) {
      final index = files.indexWhere((f) => f.path == firstPath);
      if (index >= 0) {
        final offset = (index * 76.0).toDouble(); // approximate tile height
        // ignore: unawaited_futures
        _listScrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
    // Clear the highlight after a couple of seconds.
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(_highlightPaths.clear);
    });
    setState(() {});
  }

  Future<void> _undoImports(String dirPath, List<String> paths) async {
    var removed = 0;
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
          removed++;
        }
      } catch (e) {
        debugPrint('HomeScreen: undo delete failed $path: $e');
      }
    }
    if (removed > 0 && mounted) {
      // ignore: use_build_context_synchronously
      context.read<AppState>().refresh();
      FreyaSnackBar.show(context, removed == 1 ? 'Import undone' : '$removed imports undone');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _openFile(PdfFile file) {
    final appState = context.read<AppState>();
    appState.selectFile(file);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => ViewerScreen(file: file),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showAllBookmarks() {
    final bookmarkProvider = context.read<BookmarkProvider>();
    final allBookmarks = bookmarkProvider.allBookmarks;

    if (allBookmarks.isEmpty) {
      FreyaSnackBar.show(context, 'No bookmarks yet');
      return;
    }

    // Group bookmarks by file path.
    final grouped = <String, List<Bookmark>>{};
    for (final b in allBookmarks) {
      grouped.putIfAbsent(b.filePath, () => []).add(b);
    }
    // Sort each group by page number.
    for (final list in grouped.values) {
      list.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            final entries = grouped.entries.toList()
              ..sort((a, b) {
                // Sort groups by most recent bookmark.
                final aMax = a.value.map((e) => e.createdAt).reduce(
                  (x, y) => x.isAfter(y) ? x : y,
                );
                final bMax = b.value.map((e) => e.createdAt).reduce(
                  (x, y) => x.isAfter(y) ? x : y,
                );
                return bMax.compareTo(aMax);
              });

            return Column(
              children: [
                // Handle bar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.bookmarks_rounded, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'All Bookmarks',
                        style: Theme.of(context).textTheme.titleMedium!.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${allBookmarks.length} total',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final entry = entries[i];
                      final fileName = entry.key.split('/').last;
                      final bookmarks = entry.value;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf_rounded, size: 16, color: colorScheme.error),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    fileName,
                                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                                      color: colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${bookmarks.length} bookmark${bookmarks.length > 1 ? 's' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...bookmarks.map((b) => ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.bookmark_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            title: Text(
                              b.label ?? 'Page ${b.pageNumber + 1}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              'Page ${b.pageNumber + 1}  •  ${_formatBookmarkTime(b.createdAt)}',
                              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            onTap: () {
                              Navigator.pop(ctx);
                              _openBookmarkFile(entry.key, b.pageNumber);
                            },
                          )),
                          if (i < entries.length - 1) const Divider(indent: 16, endIndent: 16, height: 1),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatBookmarkTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _openBookmarkFile(String filePath, int pageNumber) async {
    final appState = context.read<AppState>();
    // Find file in loaded files, or create a transient one.
    final existing = appState.files.where((f) => f.path == filePath).toList();
    PdfFile pdfFile;
    if (existing.isNotEmpty) {
      pdfFile = existing.first;
    } else {
      final file = File(filePath);
      if (!file.existsSync()) {
        if (mounted) {
          FreyaSnackBar.show(context, 'File not found: ${filePath.split('/').last}');
        }
        return;
      }
      pdfFile = PdfFile(
        path: filePath,
        name: filePath.split('/').last,
        sizeBytes: file.lengthSync(),
        modified: file.lastModifiedSync(),
      );
    }
    appState.selectFile(pdfFile);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => ViewerScreen(
          file: pdfFile,
          initialPage: pageNumber,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _deleteFile(PdfFile file) async {
    // Capture all provider references BEFORE any await so we don't reach
    // for BuildContext across async gaps (lint: use_build_context_synchronously).
    final fileOps = context.read<FileOperationsProvider>();
    final tagProvider = context.read<TagProvider>();
    final bookmarkProvider = context.read<BookmarkProvider>();
    final success = await fileOps.deleteFile(file);
    if (success) {
      // Clean up tag mapping for the deleted file.
      await tagProvider.forgetFile(file.path);
      // Clean up bookmarks for the deleted file.
      // BookmarkProvider is app-scoped, so calling it after a widget
      // unmount is safe — we use the pre-captured reference.
      bookmarkProvider.forgetFile(file.path);
    }
    if (mounted && success) {
      FreyaSnackBar.show(context, '${file.displayName} deleted');
    }
  }

  Future<void> _shareFile(PdfFile file) async {
    await context.read<FileOperationsProvider>().shareFile(file.path);
  }

  Future<void> _encryptFile(PdfFile file) async {
    final encryption = context.read<EncryptionProvider>();
    if (!encryption.hasPassphrase) {
      final set = await showPassphraseDialog(context);
      if (!set || !mounted) return;
    }
    final fileOps = context.read<FileOperationsProvider>();
    // Show an animated indeterminate dialog so the UI never looks frozen while
    // encryption runs (a large file may take a while). Do NOT await the dialog:
    // showDialog's future only completes when the dialog is popped, so awaiting
    // it here would deadlock before encryption ever starts.
    // ignore: use_build_context_synchronously
    unawaited(showEncryptingProgressDialog(context, fileName: file.displayName));
    final result = await fileOps.encryptFile(file);
    // ignore: use_build_context_synchronously
    closeEncryptingProgressDialog(context);
    if (!mounted) return;
    if (result != null) {
      // The original plaintext is left in place by design (only the auto-encrypt
      // path deletes it). Offer the user an explicit choice to delete it so
      // they don't end up with a confusing duplicate next to the .enc. Show the
      // dialog and delete the original ONLY if they tap Delete — default is Keep.
      final deleteOriginal = await showDeleteOriginalDialog(
        context,
        message: 'Encrypted successfully. Delete the original ${file.displayName}?',
      );
      if (deleteOriginal && mounted) {
        // The original PdfFile still points at the plaintext path, which still
        // exists, so deleteFile on it removes the plaintext copy.
        await fileOps.deleteFile(file);
        // ignore: use_build_context_synchronously
        context.read<AppState>().refresh();
      }
      if (!mounted) return;
      FreyaSnackBar.show(context, '${file.displayName} encrypted');
    } else if (fileOps.lastError != null) {
      FreyaSnackBar.show(context, fileOps.lastError!);
    }
  }

  Future<void> _decryptFile(PdfFile file) async {
    final encryption = context.read<EncryptionProvider>();
    if (!encryption.hasPassphrase) {
      final set = await showPassphraseDialog(context);
      if (!set || !mounted) return;
    }
    final fileOps = context.read<FileOperationsProvider>();
    // Do NOT await the dialog: showDialog's future completes only when the
    // dialog is popped, so awaiting here would deadlock before decrypting.
    // ignore: use_build_context_synchronously
    unawaited(showEncryptingProgressDialog(
      context,
      fileName: file.name, // keep the raw .enc name for clarity while decrypting
    ));
    final result = await fileOps.decryptFileToPlain(file);
    // ignore: use_build_context_synchronously
    closeEncryptingProgressDialog(context);
    if (!mounted) return;
    if (result != null) {
      // Refresh so the decrypted plaintext file and the removed .enc show up.
      context.read<AppState>().refresh();
      final plainName = result.split('/').last;
      FreyaSnackBar.show(context, 'Decrypted to $plainName');
    } else if (fileOps.lastError != null) {
      FreyaSnackBar.show(context, fileOps.lastError!);
    }
  }

  Future<void> _tagFile(PdfFile file) async {
    await showTagPickerDialog(context, filePath: file.path);
  }

  /// Apply tag filter and favorites-first sort on top of appState files.
  List<PdfFile> _filteredFiles(
    AppState appState,
    TagProvider tagProvider, {
    Set<String>? favoritePaths,
  }) {
    final sorted = appState.sortedFiles(favoritePaths: favoritePaths);
    final activeTagId = tagProvider.activeFilterTagId;
    if (activeTagId == null) return sorted;
    return sorted
        .where((f) => tagProvider.fileHasTag(f.path, activeTagId))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tagProvider = context.watch<TagProvider>();
    final selectionProvider = context.watch<SelectionProvider>();
    final encryptionProvider = context.watch<EncryptionProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    if (selectionProvider.isSelectionMode) {
      return Scaffold(
        appBar: _selectionAppBar(selectionProvider, encryptionProvider, colorScheme),
        body: _buildBody(
          appState,
          context.watch<SortSearchProvider>(),
          context.watch<BookmarkProvider>(),
          context.watch<FavoritesProvider>(),
          context.watch<SettingsProvider>(),
          tagProvider,
          colorScheme,
          selectionProvider: selectionProvider,
        ),
        floatingActionButton: null,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search PDFs...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                onChanged: (q) => context.read<SortSearchProvider>().setSearchQuery(q),
              )
            : Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/logo/FREYA PDF.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Freya PDF'),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close_rounded : Icons.search_rounded, size: 20),
            tooltip: _showSearch ? 'Close search' : 'Search',
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  context.read<SortSearchProvider>().setSearchQuery('');
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks_rounded, size: 20),
            tooltip: 'All bookmarks',
            onPressed: _showAllBookmarks,
          ),
          PopupMenuButton<dynamic>(
            icon: const Icon(Icons.sort_rounded, size: 20),
            tooltip: 'Sort',
            onSelected: (value) {
              if (value is SortBy) {
                final sortSearch = context.read<SortSearchProvider>();
                if (sortSearch.sortBy == value) {
                  sortSearch.sortOrder = sortSearch.sortOrder == SortOrder.asc
                      ? SortOrder.desc
                      : SortOrder.asc;
                } else {
                  sortSearch.sortBy = value;
                  sortSearch.sortOrder = SortOrder.desc;
                }
              } else if (value == 'favorites_first') {
                context.read<SortSearchProvider>().toggleFavoritesFirst();
              }
            },
            itemBuilder: (_) {
              final sortSearch = context.read<SortSearchProvider>();
              return [
                _sortItem(SortBy.name, Icons.sort_by_alpha_rounded, 'Name', sortSearch),
                _sortItem(SortBy.modified, Icons.access_time_rounded, 'Date', sortSearch),
                _sortItem(SortBy.size, Icons.data_usage_rounded, 'Size', sortSearch),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: 'favorites_first',
                  checked: sortSearch.showFavoritesFirst,
                  child: Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: sortSearch.showFavoritesFirst
                            ? Theme.of(context).colorScheme.secondary
                            : null,
                      ),
                      const SizedBox(width: 10),
                      const Text('Favorites first'),
                    ],
                  ),
                ),
              ];
            },
          ),
          IconButton(
            icon: Icon(
              tagProvider.hasTags
                  ? Icons.label_rounded
                  : Icons.label_outline_rounded,
              size: 20,
            ),
            tooltip: 'Tags',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TagsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 20),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(
        appState,
        context.watch<SortSearchProvider>(),
        context.watch<BookmarkProvider>(),
        context.watch<FavoritesProvider>(),
        context.watch<SettingsProvider>(),
        tagProvider,
        colorScheme,
        selectionProvider: null,
      ),
      floatingActionButton: FabSpeedDial(
        onPickFile: _pickImportFiles,
        onPickFolder: _pickDirectory,
      ),
    );
  }

  Widget _buildBody(
    AppState appState,
    SortSearchProvider sortSearch,
    BookmarkProvider bookmarkProvider,
    FavoritesProvider favoritesProvider,
    SettingsProvider settingsProvider,
    TagProvider tagProvider,
    ColorScheme colorScheme, {
    SelectionProvider? selectionProvider,
  }) {
    if (appState.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Scanning for PDFs...',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (appState.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                appState.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _pickDirectory,
                child: const Text('Pick a folder'),
              ),
            ],
          ),
        ),
      );
    }

    if (!appState.hasFiles) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: EmptyState(
          title: 'No PDFs found',
          subtitle: 'Open a folder to scan for PDF files',
          action: FilledButton.icon(
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Open folder'),
          ),
        ),
      );
    }

    final favoritePaths = favoritesProvider.getFavorites();
    final files = _filteredFiles(appState, tagProvider, favoritePaths: favoritePaths);
    return RefreshIndicator(
      onRefresh: () async {
        await appState.refresh();
        _staggerController.reset();
        _staggerController.forward();
      },
      child: Column(
        children: [
          // Tag filter bar — only when we have any tags to filter by.
          if (tagProvider.hasTags)
            _TagFilterBar(
              tagProvider: tagProvider,
              colorScheme: colorScheme,
            ),
          const SecureFolderCard(),
          // Live import progress (shown only while a 5+ file batch is running).
          ValueListenableBuilder<String?>(
            valueListenable: _importProgress,
            builder: (context, progress, _) {
              if (progress == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: colorScheme.surfaceContainerLow,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      progress,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: files.isEmpty
                ? _emptyFilterState(tagProvider)
                : ListView.builder(
                    controller: _listScrollController,
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return AnimatedBuilder(
                        animation: _staggerController,
                        builder: (context, child) {
                          final delay = (index * 0.03).clamp(0.0, 1.0);
                          final animValue = _staggerController.value;
                          // After animation completes, show everything. During animation, stagger items in.
                          final progress = animValue >= 1.0
                              ? 1.0
                              : (animValue - delay).clamp(0.0, 1.0);
                          return Opacity(
                            opacity: progress,
                            child: Transform.translate(
                              offset: Offset(0, 12 * (1 - progress)),
                              child: child,
                            ),
                          );
                        },
                        child: _buildFileTile(
                          file,
                          appState,
                          bookmarkProvider,
                          favoritesProvider,
                          settingsProvider,
                          tagProvider,
                          selectionProvider: selectionProvider,
                          isImported: _highlightPaths.contains(file.path),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyFilterState(TagProvider tagProvider) {
    final activeTag = tagProvider.activeFilterTag;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: EmptyState(
        title: 'No files tagged "${activeTag?.name ?? ""}"',
        subtitle: 'Try a different tag or clear the filter',
        action: TextButton.icon(
          onPressed: () => tagProvider.clearFilter(),
          icon: const Icon(Icons.clear_rounded, size: 18),
          label: const Text('Clear filter'),
        ),
      ),
    );
  }

  Widget _buildFileTile(
    PdfFile file,
    AppState appState,
    BookmarkProvider bookmarkProvider,
    FavoritesProvider favoritesProvider,
    SettingsProvider settingsProvider,
    TagProvider tagProvider, {
    SelectionProvider? selectionProvider,
    bool isImported = false,
  }) {
    // Decorate the file with its current tag IDs from the provider.
    final tagsForFile = tagProvider.getResolvedTagsForFile(file.path);
    final decorated = file.copyWith(
      tagIds: tagsForFile.map((t) => t.id).toList(growable: false),
    );

    // Bookmark count for this file
    final bookmarkCount = bookmarkProvider.allBookmarks
        .where((b) => b.filePath == file.path)
        .length;

    // Reading progress
    double? progressValue;
    final progress = settingsProvider.getLastReadProgress(file.path);
    if (progress != null && progress.totalPages > 0) {
      progressValue = (progress.page / progress.totalPages).clamp(0.0, 1.0);
    }

    // Favorite status
    final isFav = favoritesProvider.isFavorite(file.path);

    final inSelectionMode = selectionProvider != null && selectionProvider.isSelectionMode;
    final fileSelected = selectionProvider?.isSelected(file.path) ?? false;

    return FileListTile(
      file: decorated,
      tags: tagsForFile,
      isSelected: inSelectionMode ? fileSelected : appState.selectedFile?.path == file.path,
      isSelectionMode: inSelectionMode,
      onSelectToggle: selectionProvider != null
          ? () => selectionProvider.toggleSelection(file.path)
          : null,
      onTap: inSelectionMode
          ? () => selectionProvider.toggleSelection(file.path)
          : () => _openFile(decorated),
      onDelete: () => _deleteFile(decorated),
      onShare: () => _shareFile(decorated),
      onEncrypt: file.isEncrypted ? null : () => _encryptFile(decorated),
      onDecrypt: file.isEncrypted ? () => _decryptFile(decorated) : null,
      onEnterSelectionMode: selectionProvider != null && !inSelectionMode
          ? () {
              selectionProvider.enterSelectionMode();
              selectionProvider.toggleSelection(file.path);
            }
          : null,
      onTag: () => _tagFile(decorated),
      bookmarkCount: bookmarkCount,
      progressValue: progressValue,
      isFavorite: isFav,
      isEncrypted: file.isEncrypted,
      onToggleFavorite: () => favoritesProvider.toggleFavorite(file.path),
      isImported: isImported,
    );
  }

  // ---------------------------------------------------------------------------
  // Selection mode AppBar
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _selectionAppBar(
    SelectionProvider selectionProvider,
    EncryptionProvider encryptionProvider,
    ColorScheme colorScheme,
  ) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Exit selection mode',
        onPressed: () => selectionProvider.exitSelectionMode(),
      ),
      title: Text('${selectionProvider.selectedCount} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.label_outline_rounded, size: 20),
          tooltip: 'Tag selected',
          onPressed: () => _batchTag(selectionProvider.selectedPaths.toList()),
        ),
        if (encryptionProvider.hasPassphrase)
          IconButton(
            icon: const Icon(Icons.lock_open_rounded, size: 20),
            tooltip: 'Decrypt selected',
            onPressed: () => _batchDecrypt(selectionProvider.selectedPaths.toList()),
          ),
        if (encryptionProvider.hasPassphrase)
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded, size: 20),
            tooltip: 'Encrypt selected',
            onPressed: () => _batchEncrypt(selectionProvider.selectedPaths.toList()),
          ),
        IconButton(
          icon: const Icon(Icons.share_rounded, size: 20),
          tooltip: 'Share selected',
          onPressed: () => _batchShare(selectionProvider.selectedPaths.toList()),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, size: 20, color: colorScheme.error),
          tooltip: 'Delete selected',
          onPressed: () => _batchDelete(selectionProvider.selectedPaths.toList()),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (value) {
            if (value == 'secure_folder') {
              _batchMoveToSecureFolder(selectionProvider.selectedPaths.toList());
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'secure_folder',
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Move to Secure Folder'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Batch operations
  // ---------------------------------------------------------------------------

  Future<void> _batchDelete(List<String> paths) async {
    if (paths.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${paths.length} files?'),
        content: Text('$paths files will be permanently deleted.\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // ignore: use_build_context_synchronously
    final fileOps = context.read<FileOperationsProvider>();
    final bookmarkProvider = context.read<BookmarkProvider>();
    final count = await fileOps.batchDelete(paths);
    // Clean up bookmarks for deleted files
    for (final path in paths) {
      bookmarkProvider.forgetFile(path);
    }
    // ignore: use_build_context_synchronously
    context.read<SelectionProvider>().exitSelectionMode();
    if (mounted) {
      // Refresh app state
      // ignore: use_build_context_synchronously
      context.read<AppState>().refresh();
      FreyaSnackBar.show(context, '$count file${count == 1 ? '' : 's'} deleted');
    }
  }

  Future<void> _batchShare(List<String> paths) async {
    if (paths.isEmpty) return;
    final fileOps = context.read<FileOperationsProvider>();
    await fileOps.batchShare(paths);
    if (mounted) {
      context.read<SelectionProvider>().exitSelectionMode();
    }
  }

  Future<void> _batchTag(List<String> paths) async {
    if (paths.isEmpty) return;
    // Use the tag picker on the first file. After the dialog,
    // copy the chosen tags to all other selected files.
    final firstPath = paths.first;
    final changed = await showTagPickerDialog(context, filePath: firstPath);
    if (changed == true && mounted && paths.length > 1) {
      final tagProvider = context.read<TagProvider>();
      final chosenIds = tagProvider.getTagsForFile(firstPath);
      for (final path in paths.skip(1)) {
        await tagProvider.setFileTags(path, chosenIds);
      }
    }
    if (mounted) {
      context.read<SelectionProvider>().exitSelectionMode();
    }
  }

  Future<void> _batchEncrypt(List<String> paths) async {
    if (paths.isEmpty) return;
    final encryption = context.read<EncryptionProvider>();
    if (!encryption.hasPassphrase) {
      final set = await showPassphraseDialog(context);
      if (!set || !mounted) return;
    }
    final fileOps = context.read<FileOperationsProvider>();
    // Show an animated progress dialog that reports a live "X of N" count,
    // updated as each file completes via the batch callback. Keeps the UI from
    // ever looking frozen during a large batch.
    // Do NOT await the dialog: showDialog's future completes only when the
    // dialog is popped, so awaiting here would deadlock before the batch runs.
    // ignore: use_build_context_synchronously
    unawaited(showEncryptingProgressDialog(context, fileName: '', total: paths.length));
    final encrypted = await fileOps.batchEncrypt(
      paths,
      onProgress: (completed, total) =>
          // ignore: use_build_context_synchronously
          updateEncryptingProgress(context, completed),
    );
    // ignore: use_build_context_synchronously
    closeEncryptingProgressDialog(context);
    if (mounted) {
      context.read<SelectionProvider>().exitSelectionMode();
      if (encrypted.isNotEmpty) {
        // Offer to delete the original plaintext files that were successfully
        // encrypted. Default is Keep; only deletes on an explicit Delete tap.
        final deleteOriginals = await showDeleteOriginalDialog(
          context,
          message: encrypted.length == 1
              ? 'Encrypted successfully. Delete the original file?'
              : 'Encrypted successfully. Delete the ${encrypted.length} original files?',
        );
        if (deleteOriginals && mounted) {
          // Delete only the originals whose .enc was successfully created,
          // skipping any that fail (best-effort) but counting the rest.
          final encSet = encrypted.toSet();
          var deleted = 0;
          for (final originalPath in paths) {
            final encPath = '$originalPath.enc';
            if (!encSet.contains(encPath)) continue; // .enc never created
            final pdfFile = PdfFile.fromFileSystem(File(originalPath));
            final ok = await fileOps.deleteFile(pdfFile);
            if (ok) deleted++;
          }
          // ignore: use_build_context_synchronously
          context.read<AppState>().refresh();
          if (deleted > 0 && mounted) {
            FreyaSnackBar.show(context, '$deleted original file${deleted == 1 ? '' : 's'} deleted');
            return; // skip the generic "encrypted" snackbar
          }
        }
      }
      if (!mounted) return;
      FreyaSnackBar.show(context, '${encrypted.length} file${encrypted.length == 1 ? '' : 's'} encrypted');
    }
  }

  /// Decrypt multiple selected files back to plaintext. Only encrypted files
  /// are candidates; unencrypted files are skipped. Uses [decryptFileToPlain]
  /// per file with an animated progress dialog.
  Future<void> _batchDecrypt(List<String> paths) async {
    if (paths.isEmpty) return;
    final encryption = context.read<EncryptionProvider>();
    if (!encryption.hasPassphrase) {
      final set = await showPassphraseDialog(context);
      if (!set || !mounted) return;
    }
    final fileOps = context.read<FileOperationsProvider>();
    final encOnly = paths.toList();
    // Do NOT await the dialog: showDialog's future completes only when the
    // dialog is popped, so awaiting here would deadlock before decrypting.
    // ignore: use_build_context_synchronously
    unawaited(showEncryptingProgressDialog(context, fileName: '', total: encOnly.length));
    var successCount = 0;
    for (var i = 0; i < encOnly.length; i++) {
      final pdfFile = PdfFile.fromFileSystem(File(encOnly[i]));
      if (pdfFile.isEncrypted) {
        final result = await fileOps.decryptFileToPlain(pdfFile);
        if (result != null) successCount++;
      }
      // ignore: use_build_context_synchronously
      updateEncryptingProgress(context, i + 1);
    }
    // ignore: use_build_context_synchronously
    closeEncryptingProgressDialog(context);
    if (mounted) {
      context.read<SelectionProvider>().exitSelectionMode();
      context.read<AppState>().refresh();
      FreyaSnackBar.show(context, '$successCount file${successCount == 1 ? '' : 's'} decrypted');
    }
  }

  Future<void> _batchMoveToSecureFolder(List<String> paths) async {
    if (paths.isEmpty) return;
    final encryption = context.read<EncryptionProvider>();
    if (!encryption.hasPassphrase || encryption.passphrase == null) {
      final set = await showPassphraseDialog(context);
      if (!set || !mounted) return;
    }
    if (!mounted) return;
    var successCount = 0;
    for (final path in paths) {
      try {
        await SecureFolderService.importFile(path, encryption.passphrase!);
        successCount++;
      } catch (_) {
        // Skip files that can't be moved
      }
    }
    // ignore: use_build_context_synchronously
    context.read<SelectionProvider>().exitSelectionMode();
    if (mounted) {
      FreyaSnackBar.show(context, '$successCount file${successCount == 1 ? '' : 's'} moved to secure folder');
    }
  }

  PopupMenuItem<dynamic> _sortItem(
    SortBy value,
    IconData icon,
    String label,
    SortSearchProvider sortSearch,
  ) {
    final isActive = sortSearch.sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isActive ? Theme.of(context).colorScheme.primary : null),
          const SizedBox(width: 12),
          Text(label),
          if (isActive) ...[
            const Spacer(),
            Icon(
              sortSearch.sortOrder == SortOrder.asc
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal scrollable row of tag filter chips, shown above the file list
/// when the user has at least one tag. Includes an "All" chip to clear.
class _TagFilterBar extends StatelessWidget {
  final TagProvider tagProvider;
  final ColorScheme colorScheme;

  const _TagFilterBar({
    required this.tagProvider,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final tags = tagProvider.tags;
    final activeId = tagProvider.activeFilterTagId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: tags.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              final selected = activeId == null;
              return _AllChip(
                selected: selected,
                onTap: () => tagProvider.clearFilter(),
                isDark: isDark,
              );
            }
            final tag = tags[i - 1];
            return TagChip(
              tag: tag,
              selected: activeId == tag.id,
              compact: true,
              onTap: () => tagProvider.setActiveFilter(
                activeId == tag.id ? null : tag.id,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AllChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  const _AllChip({
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final bg = selected
        ? primary
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04));
    final fg = selected ? Colors.white : colorScheme.onSurfaceVariant;
    return Material(
      color: bg,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? primary
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_rounded
                    : Icons.apps_rounded,
                size: 14,
                color: fg,
              ),
              const SizedBox(width: 6),
              Text(
                'All',
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
