import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:feya_pdf/features/file_management/app_state.dart';
import 'package:feya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:feya_pdf/features/encryption/encryption_provider.dart';
import 'package:feya_pdf/features/file_management/favorites_provider.dart';
import 'package:feya_pdf/features/tags/tag_provider.dart';
import 'package:feya_pdf/features/file_management/sort_search_provider.dart';
import 'package:feya_pdf/features/file_management/selection_provider.dart';
import 'package:feya_pdf/features/file_management/file_operations_provider.dart';
import 'package:feya_pdf/features/file_management/recent_files_provider.dart';
import 'package:feya_pdf/features/file_management/scanned_paths_provider.dart';
import 'package:feya_pdf/features/settings/settings_provider.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';
import 'package:feya_pdf/features/file_management/widgets/file_list_tile.dart';
import 'package:feya_pdf/features/tags/widgets/tag_chip.dart';
import 'package:feya_pdf/features/tags/widgets/tag_picker_dialog.dart';
import 'package:feya_pdf/features/encryption/widgets/encryption_badge.dart';
import 'package:feya_pdf/features/encryption/widgets/passphrase_dialog.dart';
import 'package:feya_pdf/features/security/widgets/secure_folder_card.dart';
import 'package:feya_pdf/features/file_management/permission_service.dart';
import 'package:feya_pdf/features/file_management/intent_handler.dart';
import 'package:feya_pdf/features/security/secure_folder_service.dart';
import 'package:feya_pdf/features/viewer/viewer_screen.dart';
import 'package:feya_pdf/features/settings/settings_screen.dart';
import 'package:feya_pdf/features/tags/tags_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  late AnimationController _staggerController;

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
    if (persisted != null && await Directory(persisted).exists()) {
      await appState.loadDirectory(persisted);
      loaded = appState.allFiles.isNotEmpty || appState.error != null;
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
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    // Ensure we have permission before picking
    final hasPermission = await PermissionService.hasStoragePermission();
    if (!hasPermission && mounted) {
      final granted = await PermissionService.showPermissionDialog(context);
      if (!granted) return;
    }

    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null && mounted) {
      final appState = context.read<AppState>();
      final pathsProvider = context.read<ScannedPathsProvider>();
      await pathsProvider.persistAfterPick(result);
      await appState.loadDirectory(result);
      _staggerController.reset();
      _staggerController.forward();
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.displayName} deleted'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
    final result = await fileOps.encryptFile(file);
    if (mounted && result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.displayName} encrypted'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
          context.read<SortSearchProvider>(),
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
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Feya PDF'),
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
                            ? Colors.amber
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
        context.read<SortSearchProvider>(),
        context.watch<BookmarkProvider>(),
        context.watch<FavoritesProvider>(),
        context.watch<SettingsProvider>(),
        tagProvider,
        colorScheme,
        selectionProvider: null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickDirectory,
        tooltip: 'Open folder',
        child: const Icon(Icons.folder_open_rounded),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No PDFs found',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open a folder to scan for PDF files',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pickDirectory,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open folder'),
              ),
            ],
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
          Expanded(
            child: files.isEmpty
                ? _emptyFilterState(tagProvider, colorScheme)
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 88),
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return AnimatedBuilder(
                        animation: _staggerController,
                        builder: (context, child) {
                          final delay = (index * 0.03).clamp(0.0, 1.0);
                          final progress = (_staggerController.value - delay)
                              .clamp(0.0, 1.0);
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyFilterState(TagProvider tagProvider, ColorScheme colorScheme) {
    final activeTag = tagProvider.activeFilterTag;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No files tagged "${activeTag?.name ?? ""}"',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => tagProvider.clearFilter(),
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear filter'),
            ),
          ],
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

    return Stack(
      children: [
        FileListTile(
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
          onToggleFavorite: () => favoritesProvider.toggleFavorite(file.path),
        ),
        if (file.isEncrypted)
          Positioned(
            right: 24,
            top: 12,
            child: EncryptionBadge(),
          ),
      ],
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
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ${paths.length} files?'),
        content: Text('$paths files will be permanently deleted.\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count file${count == 1 ? '' : 's'} deleted'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
    final encrypted = await fileOps.batchEncrypt(paths);
    if (mounted) {
      context.read<SelectionProvider>().exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${encrypted.length} file${encrypted.length == 1 ? '' : 's'} encrypted'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount file${successCount == 1 ? '' : 's'} moved to secure folder'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
                style: TextStyle(
                  fontSize: 11.5,
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
