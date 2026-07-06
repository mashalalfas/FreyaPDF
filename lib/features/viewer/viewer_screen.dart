import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';
import 'package:feya_pdf/features/encryption/encryption_provider.dart';
import 'package:feya_pdf/features/settings/settings_provider.dart';
import 'package:feya_pdf/features/file_management/file_operations_provider.dart';
import 'package:feya_pdf/features/viewer/providers/search_provider.dart';
import 'package:feya_pdf/features/security/widgets/biometric_unlock_dialog.dart';
import 'package:feya_pdf/features/viewer/widgets/search_bar.dart';
import 'package:feya_pdf/features/viewer/widgets/thumbnail_grid.dart';
import 'package:feya_pdf/features/highlights/widgets/highlights_panel.dart';
import 'package:feya_pdf/features/highlights/highlight_provider.dart';
import 'package:feya_pdf/features/highlights/highlight.dart';
import 'package:feya_pdf/features/bookmarks/bookmark.dart';
import 'package:feya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:feya_pdf/features/bookmarks/widgets/bookmarks_panel.dart';

/// Color matrix that inverts all RGB channels (255 - value) while preserving alpha.
/// Used by Dark Reading Mode to create a negative effect on the PDF canvas.
const ColorFilter _invertColorFilter = ColorFilter.matrix([
  -1, 0, 0, 0, 255,
  0, -1, 0, 0, 255,
  0, 0, -1, 0, 255,
  0, 0, 0, 1, 0,
]);

class ViewerScreen extends StatefulWidget {
  final PdfFile file;
  const ViewerScreen({super.key, required this.file});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  PdfViewerController? _pdfController;
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;
  int _totalPages = 0;
  PdfDocumentRef? _documentRef;

  // Cached link annotations per page (loaded async when document is ready)
  final Map<int, List<PdfLink>> _pageLinks = {};

  // SVG-specific state
  bool _isSvgFile = false;
  String? _svgError;

  // Outline / table of contents state
  List<PdfOutlineNode>? _outline;
  bool _outlineLoading = false;

  // Search bar state
  final _searchProvider = SearchProvider();
  bool _showSearchBar = false;

  // No additional panel state needed beyond provider

  // Seek-to-page state (tapping the page counter)
  bool _showPageSeek = false;
  final _pageSeekController = TextEditingController();
  final _pageSeekFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _isSvgFile = widget.file.path.endsWith('.svg');
    _loadPdf();
    // Notify the highlight provider that this file is open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<HighlightProvider>().openFile(widget.file.path);
        context.read<BookmarkProvider>().openFile(widget.file.path);
      }
    });
  }

  Future<void> _loadPdf() async {
    // --- SVG branch ---
    if (_isSvgFile) {
      try {
        if (!await widget.file.file.exists()) {
          if (mounted) {
            setState(() {
              _error = 'File not found:\n${widget.file.path}';
              _isLoading = false;
            });
          }
          return;
        }
        if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _svgError = 'Failed to open SVG: $e';
            _isLoading = false;
          });
        }
      }
      return;
    }

    // --- PDF branch ---
    // Read all providers upfront before any async gap
    final encryption = context.read<EncryptionProvider>();
    final settings = context.read<SettingsProvider>();
    final fileOps = context.read<FileOperationsProvider>();

    final lastPage = settings.getLastReadPage(widget.file.path);
    final initialPage = (lastPage != null && lastPage > 0) ? lastPage : 1;

    // If encrypted and no passphrase, prompt with biometric unlock
    if (widget.file.isEncrypted && !encryption.hasPassphrase) {
      final set = await showBiometricUnlockDialog(context);
      if (!set || !mounted) {
        if (mounted) Navigator.pop(context);
        return;
      }
    }

    try {
      // Check file exists
      if (!await widget.file.file.exists()) {
        if (mounted) {
          setState(() {
            _error = 'File not found:\n${widget.file.path}';
            _isLoading = false;
          });
        }
        return;
      }

      // Build the PdfDocumentRef for this source
      if (widget.file.isEncrypted) {
    final bytes = await fileOps.getPdfBytes(widget.file);
        if (bytes == null || bytes.isEmpty || !mounted) {
          if (mounted) {
            setState(() {
              _error = 'Decryption failed — wrong passphrase?';
              _isLoading = false;
            });
          }
          return;
        }

        // Warn about large encrypted files (can't lazy-load these)
        if (widget.file.sizeBytes > 100 * 1024 * 1024 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Large encrypted PDF — may take a moment to load'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        _documentRef = PdfDocumentRefData(
          bytes,
          sourceName: widget.file.path,
          useProgressiveLoading: false,
        );
      } else {
        // Unencrypted: open via file path (memory-mapped / lazy page loading)
        _documentRef = PdfDocumentRefFile(
          widget.file.path,
          useProgressiveLoading: true,
        );
      }

      // Create controller — pageCount/pageNumber are available after viewer is ready
      _pdfController = PdfViewerController();

      if (mounted) {
        setState(() {
          _currentPage = initialPage;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to open PDF: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Load link annotations for a given page and cache them.
  Future<void> _loadPageLinks(PdfDocument document, int pageNumber) async {
    if (_pageLinks.containsKey(pageNumber)) return;
    try {
      final page = document.pages[pageNumber - 1];
      final links = await page.loadLinks(compact: true);
      if (mounted) {
        setState(() {
          _pageLinks[pageNumber] = links;
        });
      }
    } catch (_) {
      // Silently ignore — links are optional; render nothing on failure
    }
  }

  /// Called when the PdfViewer finishes loading the document.
  void _onViewerReady(PdfDocument? document, PdfViewerController controller) {
    if (document == null) return;
    if (!mounted) return;

    setState(() {
      _totalPages = document.pages.length;
      _currentPage = controller.pageNumber ?? _currentPage;
    });
    context.read<SettingsProvider>().setLastReadPage(
      widget.file.path,
      _currentPage,
      totalPages: _totalPages,
    );

    // Attach the search provider to the viewer controller
    // IMPORTANT: Must be inside mounted check — calling attach after
    // dispose() would create a PdfTextSearcher on a disposed ChangeNotifier.
    _searchProvider.attach(controller);

    // Pre-cache PDF page texts for highlight rendering
    context.read<HighlightProvider>().cachePageTexts(document);
    // Pre-load links for the currently visible page
    _loadPageLinks(document, controller.pageNumber ?? _currentPage);
    // Pre-load outline in the background
    _loadOutline(document);
  }

  /// Load the PDF outline (table of contents) in the background.
  ///
  /// Retries once after a short delay if the first call returns an empty
  /// outline. With `useProgressiveLoading: true` (the default for
  /// unencrypted PDFs), the document may not have parsed the outline
  /// metadata on the first attempt. A brief wait gives the progressive
  /// loader time to finish, and a second attempt typically picks up the
  /// real outline.
  Future<void> _loadOutline(PdfDocument document) async {
    if (_outlineLoading) return;
    _outlineLoading = true;
    try {
      List<PdfOutlineNode> nodes = const [];
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!mounted) return;
        nodes = await document.loadOutline();
        if (nodes.isNotEmpty) break;
        // Wait briefly before retrying so progressive loading can finish.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (mounted) {
        setState(() => _outline = nodes);
      }
    } catch (e, st) {
      // Outline is optional — log for observability but don't surface to user.
      debugPrint('Outline load failed: $e\n$st');
    } finally {
      if (mounted) {
        setState(() => _outlineLoading = false);
      }
    }
  }

  /// Called when the viewer notifies a page change.
  void _onPageChanged(int? pageNumber) {
    if (pageNumber == null || pageNumber == _currentPage) return;
    final document = _documentRef?.resolveListenable().document;
    if (document != null && pageNumber > 0 && pageNumber <= document.pages.length) {
      _loadPageLinks(document, pageNumber);
    }
    if (mounted) {
      setState(() => _currentPage = pageNumber);
      context.read<SettingsProvider>().setLastReadPage(
        widget.file.path,
        pageNumber,
        totalPages: _totalPages,
      );
    }
  }

  /// Called when the document reference notifies a document change (load / reload).
  void _onDocumentChanged(PdfDocument? document) {
    if (document == null || !mounted) return;
    setState(() => _totalPages = document.pages.length);
  }

  @override
  void dispose() {
    _searchProvider.dispose();
    _pageSeekController.dispose();
    _pageSeekFocus.dispose();
    // Clear highlight page text cache for this document
    try {
      context.read<HighlightProvider>().closeFile();
    } catch (_) {}
    // PdfViewerController is a ValueListenable; it is cleaned up by the PdfViewer widget.
    // PdfDocumentRef auto-disposes the underlying document when autoDispose=true (default).
    super.dispose();
  }

  Future<void> _shareFile() async {
    final fileOps = context.read<FileOperationsProvider>();
    await fileOps.shareFile(widget.file.path);
  }

  IconData _highlightModeIcon(BuildContext context) {
    final mode = context.watch<HighlightProvider>().highlightModeValue;
    switch (mode) {
      case 'text':
        return Icons.brush_rounded;
      case 'rectangle':
        return Icons.crop_free_rounded;
      default:
        return Icons.brush_outlined;
    }
  }

  String _highlightModeTooltip(BuildContext context) {
    final mode = context.watch<HighlightProvider>().highlightModeValue;
    switch (mode) {
      case 'text':
        return 'Text highlight mode (tap to switch)';
      case 'rectangle':
        return 'Rectangle draw mode (tap to switch)';
      default:
        return 'Highlight mode';
    }
  }

  Future<void> _saveToLocal() async {
    final fileOps = context.read<FileOperationsProvider>();

    // Ask user to pick a destination directory
    final destDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose save destination',
    );
    if (destDir == null || !mounted) return;

    final (result, newPath) = await fileOps.saveToLocal(
      widget.file.path,
      targetDir: destDir,
    );
    if (!mounted) return;

    switch (result) {
      case SaveResult.failure:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save file'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      case SaveResult.alreadyExists:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Already exists in:\n$destDir'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      case SaveResult.success:
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to:\n$destDir'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// FEATURE 1.2 — Show PDF outline / table of contents as a bottom sheet.
  void _showOutline() {
    final controller = _pdfController;
    if (controller == null) return;

    final outline = _outline;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) {
            if (outline == null || outline.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.article_outlined,
                      size: 48,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _outlineLoading
                          ? 'Loading contents…'
                          : 'No table of contents',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 15,
                      ),
                    ),
                    if (_outlineLoading) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }

            return Column(
              children: [
                // Handle bar
                Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.article_outlined,
                          size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Contents',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: cs.outlineVariant.withValues(alpha: 0.3)),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _flattenOutline(outline).length,
                    itemBuilder: (_, index) {
                      final item = _flattenOutline(outline)[index];
                      return _buildOutlineTile(ctx, item.node, item.depth);
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

  /// Flatten the outline tree into a list of (node, depth) pairs.
  List<({PdfOutlineNode node, int depth})> _flattenOutline(
    List<PdfOutlineNode> nodes, [
    int depth = 0,
  ]) {
    final result = <({PdfOutlineNode node, int depth})>[];
    for (final node in nodes) {
      result.add((node: node, depth: depth));
      result.addAll(_flattenOutline(node.children, depth + 1));
    }
    return result;
  }

  /// Build a single outline entry tile.
  Widget _buildOutlineTile(
    BuildContext ctx,
    PdfOutlineNode node,
    int depth,
  ) {
    final controller = _pdfController;
    final cs = Theme.of(ctx).colorScheme;
    final hasDest = node.dest != null;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(
        left: 16.0 + depth * 20.0,
        right: 16,
      ),
      leading: Icon(
        hasDest ? Icons.article_outlined : Icons.folder_outlined,
        size: 18,
        color: hasDest
            ? cs.onSurfaceVariant.withValues(alpha: 0.7)
            : cs.primary.withValues(alpha: 0.6),
      ),
      title: Text(
        node.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight:
              depth == 0 ? FontWeight.w600 : FontWeight.w400,
          color: cs.onSurface,
        ),
      ),
      onTap: hasDest
          ? () {
              Navigator.pop(ctx);
              if (controller != null) {
                controller.goToDest(node.dest);
              }
            }
          : null,
      enabled: hasDest,
    );
  }

  /// FEATURE 4 — Show thumbnail grid as a bottom sheet.
  void _showThumbnailGrid() {
    final controller = _pdfController;
    final documentRef = _documentRef;
    if (controller == null || documentRef == null) return;

    ThumbnailGrid.show(
      context,
      documentRef: documentRef,
      currentPage: _currentPage,
      onPageSelected: (page) => controller.goToPage(pageNumber: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    final bool showToolbar = !_isSvgFile && _totalPages > 0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: showToolbar ? 80 : kToolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            if (widget.file.isEncrypted) ...[
              Icon(Icons.lock_rounded, size: 14, color: colorScheme.tertiary),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                widget.file.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
        actions: [
          if (widget.file.isEncrypted)
            IconButton(
              icon: Icon(Icons.lock_rounded, size: 20, color: colorScheme.tertiary),
              tooltip: 'Encrypted',
              onPressed: null,
            ),
        ],
        bottom: showToolbar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // TOC
                      IconButton(
                        icon: Icon(
                          Icons.article_outlined,
                          size: 20,
                          color: _outline != null && _outline!.isNotEmpty
                              ? colorScheme.primary
                              : null,
                        ),
                        tooltip: 'Table of Contents',
                        onPressed: _showOutline,
                      ),
                      // Thumbnails
                      if (settings.showThumbnails)
                        IconButton(
                          icon: Icon(
                            Icons.view_carousel_outlined,
                            size: 20,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          tooltip: 'Thumbnails',
                          onPressed: _showThumbnailGrid,
                        ),
                      // Dark reading mode
                      IconButton(
                        icon: Icon(
                          settings.darkReadingMode
                              ? Icons.nightlight_round
                              : Icons.nightlight_outlined,
                          size: 20,
                          color: settings.darkReadingMode ? colorScheme.primary : null,
                        ),
                        tooltip: settings.darkReadingMode
                            ? 'Disable dark reading'
                            : 'Enable dark reading',
                        onPressed: () =>
                            settings.setDarkReadingMode(!settings.darkReadingMode),
                      ),
                      // Search
                      IconButton(
                        icon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: _showSearchBar ? colorScheme.primary : null,
                        ),
                        tooltip: 'Search in document',
                        onPressed: () {
                          setState(() {
                            if (_showSearchBar) _searchProvider.clearSearch();
                            _showSearchBar = !_showSearchBar;
                          });
                        },
                      ),
                      // Highlight mode
                      IconButton(
                        icon: Icon(
                          _highlightModeIcon(context),
                          size: 20,
                          color: context.watch<HighlightProvider>().highlightMode
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        tooltip: _highlightModeTooltip(context),
                        onPressed: () {
                          context.read<HighlightProvider>().toggleHighlightMode();
                        },
                      ),
                      // Highlights panel
                      IconButton(
                        icon: Icon(
                          Icons.style_rounded,
                          size: 20,
                          color: context.watch<HighlightProvider>().showPanel
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        tooltip: 'View highlights',
                        onPressed: () {
                          context.read<HighlightProvider>().togglePanel();
                        },
                      ),
                      // Bookmark
                      IconButton(
                        icon: Icon(
                          context.watch<BookmarkProvider>().fileBookmarks.any((b) => b.pageNumber == _currentPage)
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 20,
                          color: context.watch<BookmarkProvider>().fileBookmarks.any((b) => b.pageNumber == _currentPage)
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        tooltip: context.watch<BookmarkProvider>().fileBookmarks.any((b) => b.pageNumber == _currentPage)
                            ? 'Remove bookmark'
                            : 'Bookmark this page',
                        onPressed: () async {
                          final provider = context.read<BookmarkProvider>();
                          final existing = provider.fileBookmarks.where((b) => b.pageNumber == _currentPage);
                          if (existing.isNotEmpty) {
                            for (final b in existing) {
                              await provider.removeBookmark(b.id);
                            }
                          } else {
                            await provider.addBookmark(Bookmark(
                              filePath: widget.file.path,
                              pageNumber: _currentPage,
                              label: null,
                            ));
                          }
                        },
                      ),
                      // Save
                      IconButton(
                        icon: const Icon(Icons.download_rounded, size: 20),
                        tooltip: 'Save to folder',
                        onPressed: _saveToLocal,
                      ),
                      // Share
                      IconButton(
                        icon: const Icon(Icons.share_rounded, size: 20),
                        tooltip: 'Share',
                        onPressed: _shareFile,
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _showSearchBar
                ? SearchBarWidget(
                    matchCount: _searchProvider.matchCount,
                    currentMatchIndex: _searchProvider.matchCount > 0
                        ? _searchProvider.currentMatchIndex + 1
                        : 0,
                    onSearchChanged: (query) {
                      try {
                        _searchProvider.search(query);
                      } catch (e) {
                        // If pdfrx's PdfTextSearcher throws internally
                        // (e.g. document disposed mid-search), silently catch.
                        debugPrint('SearchProvider.search error: $e');
                      }
                    },
                    onNextMatch: () {
                      try {
                        _searchProvider.nextMatch();
                      } catch (e) {
                        debugPrint('SearchProvider.nextMatch error: $e');
                      }
                    },
                    onPreviousMatch: () {
                      try {
                        _searchProvider.previousMatch();
                      } catch (e) {
                        debugPrint('SearchProvider.previousMatch error: $e');
                      }
                    },
                    onClose: () {
                      _searchProvider.clearSearch();
                      setState(() => _showSearchBar = false);
                    },
                  )
                : const SizedBox.shrink(),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: context.watch<HighlightProvider>().showPanel
                ? SizedBox(
                    height: 250,
                    child: HighlightsPanel(
                      onNavigateToPage: (page) {
                        _pdfController?.goToPage(pageNumber: page);
                        context.read<HighlightProvider>().setShowPanel(false);
                      },
                      onClose: () => context
                          .read<HighlightProvider>()
                          .setShowPanel(false),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: context.watch<BookmarkProvider>().showPanel
                ? SizedBox(
                    height: 250,
                    child: BookmarksPanel(
                      onNavigateToPage: (page) {
                        _pdfController?.goToPage(pageNumber: page);
                        context.read<BookmarkProvider>().setShowPanel(false);
                      },
                      onClose: () => context
                          .read<BookmarkProvider>()
                          .setShowPanel(false),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: _buildBody(
                colorScheme,
                settings,
                key: ValueKey(settings.darkReadingMode),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !_isSvgFile && _totalPages > 0
          ? _buildPageIndicator(colorScheme)
          : null,
    );
  }

  /// Build the text selection context menu with Copy and Highlight buttons.
  ///
  /// Appears as a floating toolbar above the selection when text is
  /// selected via long-press or via the selection handles.
  Widget? _buildTextSelectionContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    if (!params.isTextSelectionEnabled ||
        !params.textSelectionDelegate.hasSelectedText) {
      return null;
    }

    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () => params.textSelectionDelegate.copyTextSelection(),
        type: ContextMenuButtonType.copy,
      ),
    ];

    // Add a Highlight button to the context menu
    items.add(
      ContextMenuButtonItem(
        onPressed: () async {
          // Get the selected text
          final selectedText =
              await params.textSelectionDelegate.getSelectedText();
          if (selectedText.isEmpty) return;

          // Get the text ranges to determine page
          final ranges =
              await params.textSelectionDelegate.getSelectedTextRanges();
          if (ranges.isEmpty) return;

          final highlight = HighlightData(
            filePath: widget.file.path,
            pageNumber: ranges.first.pageNumber,
            text: selectedText,
          );

          if (context.mounted) {
            final messenger = ScaffoldMessenger.of(context);
            final provider = context.read<HighlightProvider>();
            await provider.addHighlight(highlight);

            messenger.showSnackBar(
              SnackBar(
                content: Text('Highlight added on page ${highlight.pageNumber}'),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        label: 'Highlight',
      ),
    );

    return Align(
      alignment: Alignment.topLeft,
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: params.anchorA,
          secondaryAnchor: params.anchorB,
        ),
        buttonItems: items,
      ),
    );
  }

  Widget _buildBody(
    ColorScheme colorScheme,
    SettingsProvider settings, {
    Key? key,
  }) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              _isSvgFile ? 'Loading SVG...' : (widget.file.isEncrypted ? 'Decrypting...' : 'Loading PDF...'),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                    _svgError = null;
                  });
                  _loadPdf();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // --- SVG preview (FEATURE 2) ---
    if (_isSvgFile) {
      return _buildSvgBody(colorScheme);
    }

    // --- PDF viewer ---
    if (_documentRef == null || _pdfController == null) {
      return const Center(child: Text('No PDF loaded'));
    }

    final pdfViewerWidget = PdfViewer(
      _documentRef!,
      controller: _pdfController,
      initialPageNumber: _currentPage,
      params: PdfViewerParams(
        // FEATURE 1.5 — Continuous scroll mode vs single-page mode
        layoutPages: settings.continuousScroll
            ? (pages, params) {
                var y = params.margin;
                final layouts = <Rect>[];
                for (final page in pages) {
                  layouts.add(Rect.fromLTWH(
                    params.margin,
                    y,
                    page.width,
                    page.height,
                  ));
                  y += page.height + params.margin;
                }
                return PdfPageLayout(
                  pageLayouts: layouts,
                  documentSize: Size(
                    pages.isEmpty ? 0 : pages.first.width + params.margin * 2,
                    y,
                  ),
                );
              }
            : null,
        // FEATURE 5 (Phase 2) — Text search match highlighting
        pagePaintCallbacks: [
          _searchProvider.pagePaintCallback,
          context.read<HighlightProvider>().paintHighlights,
        ],
        matchTextColor: const Color.fromARGB(80, 255, 255, 0), // light yellow
        activeMatchTextColor: const Color.fromARGB(120, 255, 200, 0), // golden yellow
        // FEATURE 3 — Annotations / links overlay
        // pdfrx renders annotations natively (forms + appearances) by default
        // via PdfAnnotationRenderingMode.annotationAndForms, which preserves
        // clickable link hotspots without any visible highlight on the page.
        //
        // We intentionally do *not* paint translucent link badges here any
        // more: the old blue overlay produced a "pale blue selection boxes
        // everywhere" effect on PDFs with many links, which interfered with
        // normal reading. Link metadata is still loaded into `_pageLinks`
        // (see [_loadPageLinks]) for any future overlay-free features
        // (e.g. a long-press link menu), but nothing is rendered on top of
        // the PDF canvas.
        pageOverlaysBuilder: (context, pageRect, page) {
          final pageLinks = _pageLinks[page.pageNumber];
          if (pageLinks == null || pageLinks.isEmpty) return const [];
          return const [];
        },
        // FEATURE 6 — Text selection & copy
        // Enable pdfrx's built-in text selection which handles:
        // - Long-press to select words on any page
        // - Draggable start/end selection handles
        // - Semi-transparent blue selection highlight
        // - Floating toolbar with Copy button via buildContextMenu
        // - Clipboard copy via PdfTextSelectionDelegate.copyTextSelection()
        // - Dismiss on tap-elsewhere, back-navigation, or after copy
        textSelectionParams: const PdfTextSelectionParams(),
        buildContextMenu: _buildTextSelectionContextMenu,
        onDocumentChanged: _onDocumentChanged,
        onViewerReady: _onViewerReady,
        onPageChanged: _onPageChanged,
      ),
    );

    // Wrap in a Stack to overlay a gesture detector for rectangle draw mode.
    // The overlay only captures gestures when draw mode is active;
    // otherwise, it passes through to the PdfViewer below.
    final isDrawMode = context.watch<HighlightProvider>().isRectangleDrawMode;
    final drawRect = context.watch<HighlightProvider>().drawRect;

    final viewerWithDrawOverlay = Stack(
      children: [
        pdfViewerWidget,
        if (isDrawMode)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                // Convert viewport-space gesture coords to content-space
                // by adding the current scroll offset (visibleRect.topLeft).
                // The pdfrx pagePaintCallback canvas is in content space,
                // so highlights must be stored in content-space coords.
                final scrollOffset = _pdfController?.visibleRect.topLeft ?? Offset.zero;
                final contentPos = details.localPosition + scrollOffset;
                final provider = context.read<HighlightProvider>();
                provider.startDraw(contentPos, _currentPage);
              },
              onPanUpdate: (details) {
                final scrollOffset = _pdfController?.visibleRect.topLeft ?? Offset.zero;
                final contentPos = details.localPosition + scrollOffset;
                context.read<HighlightProvider>().updateDraw(
                  contentPos,
                );
              },
              onPanEnd: (_) {
                context.read<HighlightProvider>().endDraw();
              },
              onPanCancel: () {
                context.read<HighlightProvider>().cancelDraw();
              },
              child: CustomPaint(
                painter: _DrawPreviewPainter(
                  drawRect: drawRect,
                  color: Color(context.read<HighlightProvider>().fileHighlights.isNotEmpty
                      ? context.read<HighlightProvider>().fileHighlights.last.color
                      : 0xFFFFEB3B),
                ),
                size: Size.infinite,
              ),
            ),
          ),
        // Show a small mode indicator badge when in rectangle draw mode
        if (isDrawMode)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.crop_free_rounded, size: 14, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 4),
                  Text(
                    'Draw mode',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return KeyedSubtree(
      key: key,
      child: settings.darkReadingMode
          ? ColorFiltered(
              colorFilter: _invertColorFilter,
              child: viewerWithDrawOverlay,
            )
          : viewerWithDrawOverlay,
    );
  }

  /// Build the SVG preview body (FEATURE 2).
  /// Uses flutter_svg's SvgPicture.file for rendering inside an InteractiveViewer
  /// for pinch-to-zoom support. Falls back to a placeholder icon on error.
  Widget _buildSvgBody(ColorScheme colorScheme) {
    if (_svgError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'SVG preview unavailable',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              _svgError!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    try {
      return InteractiveViewer(
        minScale: 0.25,
        maxScale: 10.0,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SvgPicture.file(
              widget.file.file,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      // Fallback: placeholder icon when flutter_svg can't render
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'SVG preview unavailable',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildPageIndicator(ColorScheme colorScheme) {
    final controller = _pdfController;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    void seekToPage(String input) {
      final parsed = int.tryParse(input.trim());
      if (parsed != null && parsed >= 1 && parsed <= _totalPages) {
        controller.goToPage(pageNumber: parsed);
      }
      setState(() {
        _showPageSeek = false;
        _pageSeekController.clear();
      });
      _pageSeekFocus.unfocus();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // FEATURE 5.2 — First Page button
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: _currentPage > 1
                  ? () => controller.goToPage(pageNumber: 1)
                  : null,
              iconSize: 22,
              visualDensity: VisualDensity.compact,
              tooltip: 'First page',
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _currentPage > 1
                  ? () => controller.goToPage(pageNumber: _currentPage - 1)
                  : null,
              iconSize: 24,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            // FEATURE 5.2 — Tappable page counter → inline seek
            _showPageSeek
                ? SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _pageSeekController,
                      focusNode: _pageSeekFocus,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 1.5,
                          ),
                        ),
                        hintText: '$_totalPages',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      onSubmitted: seekToPage,
                      onTapOutside: (_) => seekToPage(_pageSeekController.text),
                    ),
                  )
                : PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'seek') {
                        setState(() {
                          _showPageSeek = true;
                          _pageSeekController.text = '';
                        });
                      } else if (value == 'bookmark') {
                        final provider = context.read<BookmarkProvider>();
                        final existing = provider.fileBookmarks
                            .where((b) => b.pageNumber == _currentPage);
                        if (existing.isNotEmpty) {
                          for (final b in existing) {
                            provider.removeBookmark(b.id);
                          }
                        } else {
                          provider.addBookmark(Bookmark(
                            filePath: widget.file.path,
                            pageNumber: _currentPage,
                            label: null,
                          ));
                        }
                      }
                    },
                    offset: const Offset(0, 40),
                    itemBuilder: (context) {
                      final isBookmarked = context
                          .read<BookmarkProvider>()
                          .fileBookmarks
                          .any((b) => b.pageNumber == _currentPage);
                      return [
                        const PopupMenuItem(
                          value: 'seek',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.edit_rounded, size: 18),
                            title: Text('Jump to page…'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (!isBookmarked)
                          const PopupMenuItem(
                            value: 'bookmark',
                            child: ListTile(
                              dense: true,
                              leading:
                                  Icon(Icons.bookmark_border_rounded, size: 18),
                              title: Text('Bookmark this page'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ];
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_currentPage / $_totalPages',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                          // Percentage (#24)
                          Text(
                            ' · ${(_currentPage / _totalPages * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color:
                                  colorScheme.primary.withValues(alpha: 0.6),
                            ),
                          ),
                          // Bookmark indicator (#08)
                          if (context
                              .watch<BookmarkProvider>()
                              .fileBookmarks
                              .any((b) => b.pageNumber == _currentPage))
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.bookmark_rounded,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _currentPage < _totalPages
                  ? () => controller.goToPage(pageNumber: _currentPage + 1)
                  : null,
              iconSize: 24,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            // FEATURE 5.2 — Last Page button
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: _currentPage < _totalPages
                  ? () => controller.goToPage(pageNumber: _totalPages)
                  : null,
              iconSize: 22,
              visualDensity: VisualDensity.compact,
              tooltip: 'Last page',
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawPreviewPainter extends CustomPainter {
  final Rect? drawRect;
  final Color color;

  _DrawPreviewPainter({required this.drawRect, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (drawRect == null) return;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(drawRect!, fillPaint);
    canvas.drawRect(drawRect!, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _DrawPreviewPainter oldDelegate) {
    return oldDelegate.drawRect != drawRect || oldDelegate.color != color;
  }
}
