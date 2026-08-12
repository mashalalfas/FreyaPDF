// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/file_management/file_operations_provider.dart';
import 'package:freya_pdf/features/security/widgets/biometric_unlock_dialog.dart';
import 'package:freya_pdf/features/viewer/widgets/thumbnail_grid.dart';
import 'package:freya_pdf/features/highlights/widgets/highlights_panel.dart';
import 'package:freya_pdf/features/highlights/highlight_provider.dart';
import 'package:freya_pdf/features/highlights/highlight.dart';
import 'package:freya_pdf/features/bookmarks/bookmark.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:freya_pdf/features/bookmarks/widgets/bookmarks_panel.dart';
import 'package:freya_pdf/features/viewer/providers/search_provider.dart';
import 'package:freya_pdf/features/viewer/widgets/search_bar.dart';
import 'package:freya_pdf/features/viewer/widgets/pdf_password_dialog.dart';
import 'package:freya_pdf/features/viewer/pdf_zoom_math.dart';
import 'package:freya_pdf/features/viewer/widgets/reader_zoom_controls.dart';
import 'package:freya_pdf/features/security/pdf_password_storage.dart';

/// Color matrix that inverts all RGB channels (255 - value) while preserving alpha.
/// Used by Dark Reading Mode to create a negative effect on the PDF canvas.
const ColorFilter _invertColorFilter = ColorFilter.matrix([
  -1,
  0,
  0,
  0,
  255,
  0,
  -1,
  0,
  0,
  255,
  0,
  0,
  -1,
  0,
  255,
  0,
  0,
  0,
  1,
  0,
]);

/// Result of laying out pages in page-turn (horizontal swipe) mode: the
/// screen-space rect for each page plus the total document size (logical px).
@immutable
class PageTurnPageLayout {
  /// Screen-space rect per page, in the same order as the input pages.
  final List<Rect> pageLayouts;

  /// Total document canvas size. Width is the cumulative page widths (plus
  /// margins); height is the tallest page (plus margins).
  final Size documentSize;

  const PageTurnPageLayout({
    required this.pageLayouts,
    required this.documentSize,
  });
}

/// Lay out PDF pages for horizontal page-turn (swipe) mode.
///
/// Pages are laid side-by-side left-to-right. Each page is scaled to fill the
/// viewport width (contentWidth / page.width), capped at 1.5x so tiny pages
/// never upscale past 150%. Pages are vertically centered within the viewport
/// height. The document scrolls horizontally — documentSize.width is the sum
/// of all page widths plus margins; documentSize.height is the tallest page
/// plus margins.
///
/// Raw PDF page sizes are in points (72 dpi). A Letter/A4 page is typically
/// ~595-612pt wide — far wider than a phone viewport (~360-410dp). Without
/// scaling such pages would overflow. This mirrors the fit-to-width philosophy
/// of single-page mode.
///
/// Pure and unit-testable: it takes the page width/height pairs and returns the
/// rects plus document size, with no dependency on pdfrx native rendering.
@visibleForTesting
PageTurnPageLayout layoutPageTurnPages(
  List<Size> pageSizes,
  double viewportWidth,
  double margin,
  double viewportHeight,
) {
  final pageLayouts = <Rect>[];
  var x = margin;
  // Content area available inside the horizontal margins.
  final contentWidth = math.max(0.0, viewportWidth - margin * 2);
  var maxHeight = 0.0;
  for (final page in pageSizes) {
    // Scale to fill the viewport width, capped at 1.5x (never upscale past
    // 150%). This guarantees edge-to-edge horizontal fill.
    final double scale;
    if (page.width <= 0 || contentWidth <= 0) {
      scale = 1.0;
    } else {
      scale = math.min(1.5, contentWidth / page.width);
    }
    final w = page.width * scale;
    final h = page.height * scale;
    // Vertically center within the viewport height.
    final y = margin + (math.max(0.0, viewportHeight - margin * 2) - h) / 2;
    pageLayouts.add(Rect.fromLTWH(x, y, w, h));
    x += w + margin;
    if (h > maxHeight) maxHeight = h;
  }
  return PageTurnPageLayout(
    pageLayouts: pageLayouts,
    documentSize: Size(x, maxHeight + margin * 2),
  );
}

/// AppBar wrapper that keeps the [AppBar] in the widget tree at all times but
/// hides it completely when `isFullscreen` is true.
///
/// Crucially it does NOT remove the AppBar from the tree (do not swap to
/// `appBar: null`): removing/re-adding it changes the Scaffold's child list,
/// which can REMOUNT the body subtree and force the PdfViewer to rebuild from
/// scratch — an ANR on large image-heavy PDFs. Two things happen instead:
///
///  1. [preferredSize] collapses to zero height in fullscreen, so the Scaffold
///     stops reserving the appBar slot and the body (the PDF viewer) expands
///     to fill the whole screen. The AppBar widget itself stays mounted in the
///     same slot, so the body only RELAYOUTS (pdfrx's `_updateLayout` handles
///     view-size changes) — it is never remounted.
///  2. The bar fades out and slides up so the collapse is visually smooth
///     rather than an instant jump.
class _AnimatedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AnimatedAppBar({required this.isFullscreen, required this.child});

  final bool isFullscreen;
  final AppBar child;

  @override
  Size get preferredSize =>
      Size.fromHeight(isFullscreen ? 0 : child.preferredSize.height);

  @override
  Widget build(BuildContext context) {
    final bool full = isFullscreen;
    return AnimatedOpacity(
      opacity: full ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: full,
        child: AnimatedSlide(
          offset: full ? const Offset(0, -1) : Offset.zero,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: child,
        ),
      ),
    );
  }
}

class ViewerScreen extends StatefulWidget {
  final PdfFile file;
  final int? initialPage;
  const ViewerScreen({super.key, required this.file, this.initialPage});

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

  // Fullscreen mode (toggle in the zoom bar). When active the AppBar is kept in
  // the tree (so the PdfViewer never relayouts / ANRs) but slid up off-screen,
  // and the system bars enter immersiveSticky via SystemChrome.
  bool _isFullscreen = false;

  // Cached link annotations per page (loaded async when document is ready)
  final Map<int, List<PdfLink>> _pageLinks = {};

  // SVG-specific state
  bool _isSvgFile = false;
  String? _svgError;

  // Outline / table of contents state
  List<PdfOutlineNode>? _outline;
  bool _outlineLoading = false;

  // Search state

  final PdfPasswordStorage _pdfPasswordStorage = PdfPasswordStorage();
  Future<String?>? _passwordPrompt;
  String? _candidatePdfPassword;
  bool _rememberCandidatePassword = false;
  bool _rememberedPasswordChecked = false;
  bool _passwordFlowUsed = false;
  int _passwordAttempts = 0;
  int _loadGeneration = 0;

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
    final loadGeneration = ++_loadGeneration;
    _documentRef = null;
    _pdfController = null;
    _passwordPrompt = null;
    _candidatePdfPassword = null;
    _rememberCandidatePassword = false;
    _rememberedPasswordChecked = false;
    _passwordFlowUsed = false;
    _passwordAttempts = 0;

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
    final initialPage =
        widget.initialPage ??
        ((lastPage != null && lastPage > 0) ? lastPage : 1);

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

      Uint8List? encryptedBytes;

      // Build the PdfDocumentRef for this source
      if (widget.file.isEncrypted) {
        encryptedBytes = await fileOps.getPdfBytes(widget.file);
        if (encryptedBytes == null || encryptedBytes.isEmpty || !mounted) {
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
              content: const Text(
                'Large encrypted PDF — may take a moment to load',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        _documentRef = PdfDocumentRefData(
          encryptedBytes,
          sourceName: widget.file.path,
          passwordProvider: _providePdfPassword,
          key: PdfDocumentRefKey('${widget.file.path}#viewer-$loadGeneration'),
          useProgressiveLoading: false,
        );
      } else {
        // Unencrypted: open via file path (memory-mapped / lazy page loading)
        _documentRef = PdfDocumentRefFile(
          widget.file.path,
          passwordProvider: _providePdfPassword,
          key: PdfDocumentRefKey('${widget.file.path}#viewer-$loadGeneration'),
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

  /// Supplies passwords to both the viewer and the search document. pdfrx
  /// calls this again after a rejected password, so a cancelled dialog stops
  /// the retry loop by returning null.
  Future<String?> _providePdfPassword() async {
    final activePrompt = _passwordPrompt;
    if (activePrompt != null) return activePrompt;

    final prompt = _providePdfPasswordOnce();
    _passwordPrompt = prompt;
    try {
      return await prompt;
    } finally {
      if (identical(_passwordPrompt, prompt)) _passwordPrompt = null;
    }
  }

  Future<String?> _providePdfPasswordOnce() async {
    if (!mounted) return null;
    _passwordFlowUsed = true;

    if (!_rememberedPasswordChecked) {
      _rememberedPasswordChecked = true;
      final remembered = await _pdfPasswordStorage.read(widget.file.path);
      if (remembered != null && remembered.isNotEmpty) {
        _candidatePdfPassword = remembered;
        _rememberCandidatePassword = true;
        _passwordAttempts++;
        return remembered;
      }
    }

    if (!mounted) return null;
    final result = await showPdfPasswordDialog(
      context,
      isRetry: _passwordAttempts > 0,
    );
    if (result == null || result.password.isEmpty) return null;

    _candidatePdfPassword = result.password;
    _rememberCandidatePassword = result.remember;
    _passwordAttempts++;
    return result.password;
  }

  Future<void> _rememberPdfPassword() async {
    if (!_passwordFlowUsed) return;
    final password = _candidatePdfPassword;
    if (!_rememberCandidatePassword) {
      try {
        await _pdfPasswordStorage.delete(widget.file.path);
      } catch (e) {
        debugPrint('Viewer: failed to forget PDF password: $e');
      }
      return;
    }
    if (password == null || password.isEmpty) {
      return;
    }
    try {
      await _pdfPasswordStorage.write(widget.file.path, password);
    } catch (e) {
      debugPrint('Viewer: failed to remember PDF password: $e');
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
    unawaited(_rememberPdfPassword());
    context.read<SettingsProvider>().setLastReadPage(
      widget.file.path,
      _currentPage,
      totalPages: _totalPages,
    );

    // Attach search provider — controller is now wired up so search can
    // navigate to matches.
    final searchProvider = context.read<SearchProvider>();
    searchProvider.attach(controller);

    // Pre-load links for the currently visible page
    final visiblePage = controller.pageNumber ?? _currentPage;
    _loadPageLinks(document, visiblePage);
    _loadHighlightPageText(document, visiblePage);
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
    if (document != null &&
        pageNumber > 0 &&
        pageNumber <= document.pages.length) {
      _loadPageLinks(document, pageNumber);
      _loadHighlightPageText(document, pageNumber);
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

  void _loadHighlightPageText(PdfDocument document, int pageNumber) {
    unawaited(
      context.read<HighlightProvider>().cachePageText(document, pageNumber),
    );
  }

  /// Called when the document reference notifies a document change (load / reload).
  void _onDocumentChanged(PdfDocument? document) {
    if (document == null || !mounted) return;
    setState(() => _totalPages = document.pages.length);
  }

  void _onDocumentLoadFinished(PdfDocumentRef documentRef, bool succeeded) {
    if (succeeded || !mounted) return;
    final error = documentRef.resolveListenable().error;
    final message = error is PdfPasswordException
        ? 'This PDF could not be opened with the supplied password.'
        : 'Failed to open PDF: ${error ?? 'unknown error'}';
    Future<void>.microtask(() {
      if (!mounted) return;
      setState(() {
        _error = message;
        _isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _pageSeekController.dispose();
    _pageSeekFocus.dispose();
    // Restore the system bars (edgeToEdge) when leaving the viewer so other
    // screens are not left in immersive mode.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Clear highlight page text cache for this document
    try {
      context.read<HighlightProvider>().closeFile();
    } catch (_) {}
    // PdfViewerController is a ValueListenable; it is cleaned up by the PdfViewer widget.
    // PdfDocumentRef auto-disposes the underlying document when autoDispose=true (default).
    super.dispose();
  }

  /// Toggles fullscreen mode: hides the system bars via SystemChrome and slides
  /// the AppBar off-screen (kept in the tree to avoid a PdfViewer relayout).
  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    SystemChrome.setEnabledSystemUIMode(
      _isFullscreen
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _shareFile() async {
    final fileOps = context.read<FileOperationsProvider>();
    await fileOps.shareFile(widget.file.path);
  }

  IconData _highlightModeIcon(BuildContext context) {
    final mode = context.watch<HighlightProvider>().highlightModeValue;
    switch (mode) {
      case 'rectangle':
        return Icons.crop_free_rounded;
      default:
        return Icons.brush_outlined;
    }
  }

  String _highlightModeTooltip(BuildContext context) {
    final mode = context.watch<HighlightProvider>().highlightModeValue;
    switch (mode) {
      case 'rectangle':
        return 'Draw mode ON (tap to turn off)';
      default:
        return 'Highlight (tap to enable draw mode)';
    }
  }

  /// Build the search button that shows indexing/ready status.
  Widget _buildSearchButton(ColorScheme colorScheme) {
    return Consumer<SearchProvider>(
      builder: (context, provider, _) {
        IconData icon;
        Color? iconColor;
        String tooltip;
        VoidCallback? onPressed;

        switch (provider.indexStatus) {
          case IndexStatus.indexing:
            icon = Icons.search_rounded;
            iconColor = colorScheme.primary;
            tooltip = 'Search indexed pages (still indexing)';
            onPressed = () => provider.toggleSearchBar();
          case IndexStatus.noText:
            icon = Icons.search_off_rounded;
            iconColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
            tooltip = 'Search in document';
            onPressed = () => provider.toggleSearchBar();
          case IndexStatus.notIndexed:
            icon = Icons.search_rounded;
            iconColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
            tooltip = 'Search in document';
            onPressed = () => provider.toggleSearchBar();
          case IndexStatus.error:
            icon = Icons.error_outline_rounded;
            iconColor = colorScheme.error;
            tooltip = 'Search in document';
            onPressed = () => provider.toggleSearchBar();
          case IndexStatus.unavailable:
            icon = Icons.search_off_rounded;
            iconColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
            tooltip = provider.searchUnavailableReason ?? 'Search in document';
            onPressed = () => provider.toggleSearchBar();
          case IndexStatus.ready:
            icon = Icons.search_rounded;
            iconColor = provider.showSearchBar
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
            tooltip = 'Search in document';
            onPressed = () {
              provider.toggleSearchBar();
            };
        }

        return IconButton(
          icon: provider.indexStatus == IndexStatus.indexing
              ? _IndexingAnimation(color: colorScheme.primary)
              : Icon(icon, size: 20, color: iconColor),
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
        );
      },
    );
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return;
      case SaveResult.alreadyExists:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Already exists in:\n$destDir'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
                      Icon(Icons.article_outlined, size: 20, color: cs.primary),
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
  Widget _buildOutlineTile(BuildContext ctx, PdfOutlineNode node, int depth) {
    final controller = _pdfController;
    final cs = Theme.of(ctx).colorScheme;
    final hasDest = node.dest != null;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 16.0 + depth * 20.0, right: 16),
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
          fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.w400,
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

  /// Convert a viewport-space point (from a GestureDetector over the
  /// Positioned.fill overlay) to content-space (the same coord space as
  /// the pdfrx pagePaintCallback canvas).
  ///
  /// `visibleRect` is in content-space (unzoomed units, per pdfrx 1.3.5).
  /// Conversion: `content = visibleRect.topLeft + viewport / zoom`,
  /// where `zoom = viewSize.width / visibleRect.width`.
  Offset _viewportToContent(Offset viewport) {
    final visible = safeVisibleRect();
    final size = safeViewSize();
    if (visible == null || size == null || visible.width <= 0) {
      return viewport; // best-effort before viewer is ready
    }
    final invZoom = visible.width / size.width; // = 1 / zoom
    return visible.topLeft + viewport * invZoom;
  }

  /// Safely read [_pdfController]'s `visibleRect`. pdfrx 1.3.5 internally
  /// dereferences `_viewSize!`, which throws "Null check operator used on
  /// a null value" when the viewer has not been laid out yet (e.g. draw
  /// mode is activated during the brief window between document open and
  /// the first LayoutBuilder pass). This wrapper catches that and returns
  /// `null` so callers can fall back gracefully.
  ///
  /// Exposed package-private (no underscore) so tests can drive it with a
  /// real [PdfViewerController] in the unattached state.
  @visibleForTesting
  Rect? safeVisibleRect() {
    try {
      return _pdfController?.visibleRect;
    } catch (_) {
      return null;
    }
  }

  /// Safely read [_pdfController]'s `viewSize`. See [safeVisibleRect] for
  /// the rationale — pdfrx's `viewSize` getter is `_state._viewSize!`.
  @visibleForTesting
  Size? safeViewSize() {
    try {
      return _pdfController?.viewSize;
    } catch (_) {
      return null;
    }
  }

  /// Safely read [_pdfController]'s `currentZoom`. May throw when the
  /// viewer is not laid out yet (same trap as [safeVisibleRect]); returns
  /// null on that path so callers can bail out gracefully.
  @visibleForTesting
  double? safeCurrentZoom() {
    try {
      return _pdfController?.isReady == true
          ? _pdfController?.currentZoom
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Apply a zoom step ([PdfZoomMath.zoomIn] / [PdfZoomMath.zoomOut]) while
  /// keeping the page centred.
  ///
  /// Device feedback reported pinch-zooming drifting the page off-centre on
  /// large PDFs. The root cause is that pdfrx's InteractiveViewer runs with
  /// an infinite boundary margin (`boundaryMargin: double.infinity` because
  /// no `scrollPhysics` is configured), so after a gesture the viewport is
  /// never re-clamped or re-centred and the page edge can end up off-screen.
  ///
  /// Instead of zooming about the gesture focal point (which sits off the
  /// page centre and accumulates translation), this anchors every step on
  /// the document point currently under the VIEWPORT centre via
  /// [PdfViewerController.setZoom], so the page stays perfectly centred at
  /// any zoom level. The numeric step itself is a pure transform in
  /// [PdfZoomMath] so its direction is unit tested.
  @visibleForTesting
  Future<void> zoomByFactor(double factor) async {
    final controller = _pdfController;
    if (controller == null || controller.isReady != true) return;
    try {
      final next = PdfZoomMath.step(
        controller.currentZoom,
        factor,
        min: controller.minScale,
        max: controller.maxScale,
      );
      // `centerPosition` is the document coordinate under the centre of the
      // viewport. Passing it as the zoom centre keeps that point pinned to
      // the viewport centre, so the page never drifts off-centre.
      await controller.setZoom(
        controller.centerPosition,
        next,
        duration: const Duration(milliseconds: 200),
      );
    } catch (_) {
      // Viewer not ready / matrix lock — nothing safe to do; ignore.
    }
  }

  /// Reset the view so the current page is fully visible AND centred.
  ///
  /// Uses pdfrx's `/Fit` matrix (`calcMatrixForFit`), which scales the page
  /// to fit the smallest viewport dimension and centres it — restoring the
  /// fully-visible, centred layout even after the user zoomed in and the
  /// page had drifted partially off-screen.
  @visibleForTesting
  Future<void> resetViewAndCenter() async {
    final controller = _pdfController;
    if (controller == null || controller.isReady != true) return;
    try {
      final fit = controller.calcMatrixForFit(pageNumber: _currentPage);
      if (fit != null) {
        await controller.goTo(fit, duration: const Duration(milliseconds: 200));
      }
    } catch (_) {
      // Viewer not ready — ignore.
    }
  }

  /// Re-fit the current page after a device rotation (single-page mode).
  ///
  /// pdfrx's `/Fit` (used on initial load) scales to the SMALLEST viewport
  /// dimension, which in landscape is the HEIGHT — leaving side margins.
  /// The user-facing spec is: rotating must auto-zoom the page so it FILLS
  /// the screen width (vertical content overflows and scrolls; horizontal is
  /// always fully visible). Landscape therefore uses `calcMatrixFitWidthForPage`;
  /// portrait keeps the classic fit (which for portrait pages is width-fit
  /// anyway). Only fires on an actual orientation flip, not every resize
  /// (keyboard, split-screen, etc.).
  Future<void> _refitAfterRotation(
    Size viewSize,
    Size? oldViewSize,
    PdfViewerController controller,
  ) async {
    if (oldViewSize == null) return;
    final wasLandscape = oldViewSize.width > oldViewSize.height;
    final isLandscape = viewSize.width > viewSize.height;
    if (wasLandscape == isLandscape) return; // resize, not a flip
    if (controller.isReady != true) return;
    try {
      final page = controller.pageNumber ?? _currentPage;
      final fit = isLandscape
          ? controller.calcMatrixFitWidthForPage(pageNumber: page)
          : controller.calcMatrixForFit(pageNumber: page);
      if (fit != null) {
        await controller.goTo(fit, duration: const Duration(milliseconds: 200));
      }
    } catch (_) {
      // Viewer not ready / matrix lock — nothing safe to do; ignore.
    }
  }

  /// Snap-to-page handler for page-turn mode.
  ///
  /// Called by pdfrx's `onInteractionEnd` when the user lifts their fingers
  /// after swiping. Reads `controller.layout.pageLayouts` to find the page
  /// whose center x is nearest the current viewport center, then animates to
  /// that page. All pdfrx getters are guarded with try/catch because they can
  /// throw before the viewer is fully laid out.
  void _onPageTurnInteractionEnd(ScaleEndDetails details) {
    final controller = _pdfController;
    if (controller == null || controller.isReady != true) return;
    try {
      final layout = controller.layout;
      final pageLayouts = layout.pageLayouts;
      if (pageLayouts.isEmpty) return;

      final visible = safeVisibleRect();
      if (visible == null) return;

      final viewportCenterX = visible.center.dx;

      // Find the page whose center x is nearest the viewport center.
      int nearestPage = 0;
      double nearestDistance = double.infinity;
      for (var i = 0; i < pageLayouts.length; i++) {
        final pageCenterX = pageLayouts[i].center.dx;
        final dist = (pageCenterX - viewportCenterX).abs();
        if (dist < nearestDistance) {
          nearestDistance = dist;
          nearestPage = i;
        }
      }

      // pdfrx page numbers are 1-based.
      controller.goToPage(
        pageNumber: nearestPage + 1,
        duration: const Duration(milliseconds: 250),
      );
    } catch (_) {
      // Viewer not ready or layout not available — nothing safe to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (SearchProvider.kTraceSearchStorm) SearchProvider.stormBuildCount++;
    final colorScheme = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    final bool showToolbar = !_isSvgFile && _totalPages > 0;
    // Landscape uses a slim, Google-Drive-density top bar: all action buttons
    // live in the AppBar actions row (compact 48 high) and the portrait-only
    // bottom toolbar row is removed. Portrait keeps the taller 80-px bar +
    // bottom row unchanged.
    final bool landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      appBar: _AnimatedAppBar(
        isFullscreen: _isFullscreen,
        child: AppBar(
          toolbarHeight: showToolbar
              ? (landscape ? 48 : 80)
              : kToolbarHeight,
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
              icon: Icon(
                Icons.lock_rounded,
                size: 20,
                color: colorScheme.tertiary,
              ),
              tooltip: 'Encrypted',
              onPressed: null,
            ),
          // Landscape: compact single-row actions (Google Drive density).
          if (landscape && showToolbar) ...[
            _buildSearchButton(colorScheme),
            IconButton(
              icon: Icon(
                Icons.article_outlined,
                size: 20,
                color: _outline != null && _outline!.isNotEmpty
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Table of Contents',
              onPressed: _showOutline,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(
                _highlightModeIcon(context),
                size: 20,
                color: context.watch<HighlightProvider>().highlightMode
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              tooltip: _highlightModeTooltip(context),
              onPressed: () =>
                  context.read<HighlightProvider>().toggleHighlightMode(),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(
                context.watch<BookmarkProvider>().fileBookmarks.any(
                      (b) => b.pageNumber == _currentPage,
                    )
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                size: 20,
                color: context.watch<BookmarkProvider>().fileBookmarks.any(
                      (b) => b.pageNumber == _currentPage,
                    )
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              tooltip: 'Bookmark this page (long-press for list)',
              onPressed: () async {
                final provider = context.read<BookmarkProvider>();
                final existing = provider.fileBookmarks.where(
                  (b) => b.pageNumber == _currentPage,
                );
                if (existing.isNotEmpty) {
                  for (final b in existing) {
                    await provider.removeBookmark(b.id);
                  }
                } else {
                  await provider.addBookmark(
                    Bookmark(
                      filePath: widget.file.path,
                      pageNumber: _currentPage,
                      label: null,
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 20),
              tooltip: 'Share',
              onPressed: _shareFile,
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              tooltip: 'More options',
              onSelected: (value) {
                switch (value) {
                  case 'dark':
                    settings.setDarkReadingMode(!settings.darkReadingMode);
                    break;
                  case 'thumbnails':
                    _showThumbnailGrid();
                    break;
                  case 'fullscreen':
                    _toggleFullscreen();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'dark',
                  child: Text(
                    settings.darkReadingMode
                        ? 'Disable dark reading'
                        : 'Enable dark reading',
                  ),
                ),
                const PopupMenuItem(
                  value: 'thumbnails',
                  child: Text('Thumbnails'),
                ),
                PopupMenuItem(
                  value: 'fullscreen',
                  child: Text(
                    _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                  ),
                ),
              ],
            ),
          ],
        ],
        bottom: showToolbar && !landscape
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
                        visualDensity: VisualDensity.compact,
                      ),
                      // Thumbnails
                      if (settings.showThumbnails)
                        IconButton(
                          icon: Icon(
                            Icons.view_carousel_outlined,
                            size: 20,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          tooltip: 'Thumbnails',
                          onPressed: _showThumbnailGrid,
                          visualDensity: VisualDensity.compact,
                        ),
                      // Dark reading mode
                      IconButton(
                        icon: Icon(
                          settings.darkReadingMode
                              ? Icons.nightlight_round
                              : Icons.nightlight_outlined,
                          size: 20,
                          color: settings.darkReadingMode
                              ? colorScheme.primary
                              : null,
                        ),
                        tooltip: settings.darkReadingMode
                            ? 'Disable dark reading'
                            : 'Enable dark reading',
                        onPressed: () => settings.setDarkReadingMode(
                          !settings.darkReadingMode,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),

                      // Highlight mode
                      IconButton(
                        icon: Icon(
                          _highlightModeIcon(context),
                          size: 20,
                          color:
                              context.watch<HighlightProvider>().highlightMode
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                        tooltip: _highlightModeTooltip(context),
                        onPressed: () {
                          context
                              .read<HighlightProvider>()
                              .toggleHighlightMode();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                      // Search in document
                      _buildSearchButton(colorScheme),
                      // Highlights panel
                      IconButton(
                        icon: Icon(
                          Icons.style_rounded,
                          size: 20,
                          color: context.watch<HighlightProvider>().showPanel
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                        tooltip: 'View highlights',
                        onPressed: () {
                          context.read<HighlightProvider>().togglePanel();
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                      // Bookmark
                      GestureDetector(
                        onLongPress: () {
                          context.read<BookmarkProvider>().setShowPanel(
                            !context.read<BookmarkProvider>().showPanel,
                          );
                        },
                        child: IconButton(
                          icon: Icon(
                            context.watch<BookmarkProvider>().fileBookmarks.any(
                                  (b) => b.pageNumber == _currentPage,
                                )
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            size: 20,
                            color:
                                context
                                    .watch<BookmarkProvider>()
                                    .fileBookmarks
                                    .any((b) => b.pageNumber == _currentPage)
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.7,
                                  ),
                          ),
                          tooltip:
                              context
                                  .watch<BookmarkProvider>()
                                  .fileBookmarks
                                  .any((b) => b.pageNumber == _currentPage)
                              ? 'Remove bookmark'
                              : 'Bookmark this page (long-press for list)',
                          onPressed: () async {
                            final provider = context.read<BookmarkProvider>();
                            final existing = provider.fileBookmarks.where(
                              (b) => b.pageNumber == _currentPage,
                            );
                            if (existing.isNotEmpty) {
                              for (final b in existing) {
                                await provider.removeBookmark(b.id);
                              }
                            } else {
                              await provider.addBookmark(
                                Bookmark(
                                  filePath: widget.file.path,
                                  pageNumber: _currentPage,
                                  label: null,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      // Save
                      IconButton(
                        icon: const Icon(Icons.download_rounded, size: 20),
                        tooltip: 'Save to folder',
                        onPressed: _saveToLocal,
                        visualDensity: VisualDensity.compact,
                      ),
                      // Share
                      IconButton(
                        icon: const Icon(Icons.share_rounded, size: 20),
                        tooltip: 'Share',
                        onPressed: _shareFile,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              )
            : null,
        ),
      ),
      // The search bar is an OVERLAY over the viewer, not an item in the
      // layout Column. When it lived in the Column inside an AnimatedSize,
      // opening it RESIZED the PdfViewer — and pdfrx then re-rendered the
      // visible page at the new size, repeatedly across the animation. On
      // large image-heavy PDFs that is a multi-second CPU storm which trips
      // Android's input-dispatch timeout -> ANR (reproduced on the HMD
      // Skyline). As an overlay, toggling the bar never changes the
      // viewer's size, so no re-render is triggered and opening the search
      // bar is truly UI-only and safe.
      body: Stack(
        children: [
          Column(
            children: [
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
                            context.read<HighlightProvider>().setShowPanel(
                              false,
                            );
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
                            context.read<BookmarkProvider>().setShowPanel(
                              false,
                            );
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
          // Consumer-scoped so SearchProvider notifications (search bar
          // open/close, match updates) rebuild ONLY this overlay subtree,
          // not the main build — rebuilding the main build reconstructs the
          // PdfViewer and triggers a pdfrx re-render, which ANRs on large
          // image-heavy PDFs.
          //
          // RepaintBoundary: isolate the overlay's paint layer from the
          // PdfViewer (wrapped in its own RepaintBoundary above) so the
          // search bar mounting/animating never forces a viewer repaint.
          // No AnimatedSwitcher: a cross-fade would schedule ~11 paint
          // frames, each of which (without the boundaries) could pull the
          // viewer into a re-render cascade. Instant show/hide is safer.
          Consumer<SearchProvider>(
            builder: (context, search, _) => Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                child: search.showSearchBar
                    ? SearchBarWidget(
                        key: const ValueKey('freya-search-bar-overlay'),
                        matchCount: search.matchCount,
                        currentMatchIndex: search.currentMatchIndex + 1,
                        searchUnavailableReason: search.searchUnavailableReason,
                        searchTruncated: search.searchTruncated,
                        onSearchChanged: search.search,
                        onNextMatch: search.nextMatch,
                        onPreviousMatch: search.previousMatch,
                        onClose: search.closeSearchBar,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          // Floating zoom controls (user-adopted fix for off-centre page +
          // broken-feeling pinch on large PDFs). Only shown for the loaded
          // PDF reader, not for SVG previews. Lives in this outer Stack so
          // it overlays the viewer without resizing the PdfViewer (which
          // would trigger a pdfrx re-render / ANR on large files).
          if (!_isSvgFile && _totalPages > 0 && _pdfController != null)
            Positioned(
              right: 16,
              bottom: 16,
              child: RepaintBoundary(
                child: ReaderZoomControls(
                  onZoomIn: () =>
                      unawaited(zoomByFactor(PdfZoomMath.kZoomInFactor)),
                  onZoomOut: () =>
                      unawaited(zoomByFactor(PdfZoomMath.kZoomOutFactor)),
                  onReset: () => unawaited(resetViewAndCenter()),
                  onToggleFullscreen: _toggleFullscreen,
                  isFullscreen: _isFullscreen,
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
          final selectedText = await params.textSelectionDelegate
              .getSelectedText();
          if (selectedText.isEmpty) return;

          // Get the text ranges to determine page
          final ranges = await params.textSelectionDelegate
              .getSelectedTextRanges();
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
                content: Text(
                  'Highlight added on page ${highlight.pageNumber}',
                ),
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
              _isSvgFile
                  ? 'Loading SVG...'
                  : (widget.file.isEncrypted
                        ? 'Decrypting...'
                        : 'Loading PDF...'),
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
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: colorScheme.error,
              ),
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

    final pdfViewerWidget = LayoutBuilder(
      builder: (context, constraints) {
        // Capture the viewport width so the page-turn layout (which pdfrx
        // calls with only the page list + PdfViewerParams — no viewport size)
        // can scale each page to fit the screen width.
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        return PdfViewer(
          _documentRef!,
          controller: _pdfController,
          initialPageNumber: _currentPage,
          params: PdfViewerParams(
            // FEATURE 1.5 — Page-turn (horizontal swipe) mode vs single-page mode.
            //
            // Single-page mode uses pdfrx's /Fit matrix (calcMatrixForFit) which
            // scales the page to fit the smallest viewport dimension and centres it.
            //
            // Page-turn mode builds a custom horizontal page stack: pages are laid
            // side-by-side left-to-right, each scaled to fill the viewport width
            // (capped at 1.5x). The document scrolls horizontally and snaps to the
            // nearest page on release via onInteractionEnd.
            layoutPages: settings.pageTurnMode
                ? (pages, params) {
                    final laidOut = layoutPageTurnPages(
                      [for (final p in pages) Size(p.width, p.height)],
                      viewportWidth,
                      params.margin,
                      viewportHeight,
                    );
                    return PdfPageLayout(
                      pageLayouts: laidOut.pageLayouts,
                      documentSize: laidOut.documentSize,
                    );
                  }
                : null,
            // FEATURE 5 (Phase 2) — Text search match highlighting
            pagePaintCallbacks: [
              context.read<SearchProvider>().paintSearchMatches,
              context.read<HighlightProvider>().paintHighlights,
            ],
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
            onDocumentLoadFinished: _onDocumentLoadFinished,
            onViewerReady: _onViewerReady,
            onViewSizeChanged: settings.pageTurnMode
                ? null
                : _refitAfterRotation,
            onPageChanged: _onPageChanged,
            onInteractionEnd: settings.pageTurnMode
                ? _onPageTurnInteractionEnd
                : null,
          ),
        );
      },
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
                // Convert viewport-space gesture coords to content-space,
                // accounting for both scroll offset and current zoom.
                final contentPos = _viewportToContent(details.localPosition);
                final provider = context.read<HighlightProvider>();
                provider.startDraw(contentPos, _currentPage);
              },
              onPanUpdate: (details) {
                context.read<HighlightProvider>().updateDraw(
                  _viewportToContent(details.localPosition),
                );
              },
              onPanEnd: (_) {
                context.read<HighlightProvider>().endDraw().then((_) {
                  // Force the PdfViewer to repaint so the committed
                  // rectangle highlight appears immediately.  Without this,
                  // _widgetUpdated returns early (doChangesRequireReload is
                  // false when only pagePaintCallbacks changed) and the
                  // RepaintBoundary may reuse a stale layer.
                  if (mounted &&
                      _pdfController?.isReady == true) {
                    _pdfController?.invalidate();
                  }
                });
              },
              onPanCancel: () {
                context.read<HighlightProvider>().cancelDraw();
              },
              child: CustomPaint(
                painter: _DrawPreviewPainter(
                  drawRect: drawRect,
                  contentToViewport: safeVisibleRect()?.topLeft ?? Offset.zero,
                  contentToViewportScale: () {
                    final v = safeVisibleRect();
                    final s = safeViewSize();
                    if (v == null || s == null || v.width <= 0) return 1.0;
                    return s.width / v.width; // = zoom
                  }(),
                  color: Color(
                    context.read<HighlightProvider>().fileHighlights.isNotEmpty
                        ? context
                              .read<HighlightProvider>()
                              .fileHighlights
                              .last
                              .color
                        : 0xFFFFEB3B,
                  ),
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
            child: GestureDetector(
              onTap: () =>
                  context.read<HighlightProvider>().toggleHighlightMode(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                    Icon(
                      Icons.crop_free_rounded,
                      size: 14,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Draw mode — tap to exit',
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
          ),
      ],
    );

    return KeyedSubtree(
      key: key,
      child: RepaintBoundary(
        // Isolate the PdfViewer's paint layer from sibling overlays (search
        // bar, draw-mode badge).
        child: ExcludeSemantics(
          // Exclude the PdfViewer from the Flutter semantics tree. When
          // SemanticsBinding.instance.semanticsEnabled is true (which it is
          // on many Android devices where TalkBack / accessibility services
          // are running), pdfrx builds Focus+Semantics widgets for every
          // line of visible text. This creates a large semantics subtree
          // (~500 nodes for 3 visible text pages). When the search bar's
          // TextField+FocuNode mounts and Flutter reconciles the semantics
          // tree synchronously on the main thread, processing pdfrx's nodes
          // blocks the thread for 5s+ → "Input dispatching timed out for
          // FocusEvent" ANR.
          child: settings.darkReadingMode
              ? ColorFiltered(
                  colorFilter: _invertColorFilter,
                  child: viewerWithDrawOverlay,
                )
              : viewerWithDrawOverlay,
        ),
      ),
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
            Icon(
              Icons.broken_image_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'SVG preview unavailable',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              _svgError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
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
              placeholderBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
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
            Icon(
              Icons.insert_drive_file_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
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
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
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
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
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
                        final existing = provider.fileBookmarks.where(
                          (b) => b.pageNumber == _currentPage,
                        );
                        if (existing.isNotEmpty) {
                          for (final b in existing) {
                            provider.removeBookmark(b.id);
                          }
                        } else {
                          provider.addBookmark(
                            Bookmark(
                              filePath: widget.file.path,
                              pageNumber: _currentPage,
                              label: null,
                            ),
                          );
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
                              leading: Icon(
                                Icons.bookmark_border_rounded,
                                size: 18,
                              ),
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
                              color: colorScheme.primary.withValues(alpha: 0.6),
                            ),
                          ),
                          // Bookmark indicator (#08)
                          if (context
                              .watch<BookmarkProvider>()
                              .fileBookmarks
                              .any((b) => b.pageNumber == _currentPage))
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
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
  final Rect? drawRect; // content-space
  final Offset contentToViewport; // = visibleRect.topLeft
  final double contentToViewportScale; // = zoom = viewSize.w / visibleRect.w
  final Color color;

  _DrawPreviewPainter({
    required this.drawRect,
    required this.contentToViewport,
    required this.contentToViewportScale,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (drawRect == null) return;

    // content -> viewport: `viewport = (content - topLeft) * zoom`
    final r = Rect.fromLTRB(
      (drawRect!.left - contentToViewport.dx) * contentToViewportScale,
      (drawRect!.top - contentToViewport.dy) * contentToViewportScale,
      (drawRect!.right - contentToViewport.dx) * contentToViewportScale,
      (drawRect!.bottom - contentToViewport.dy) * contentToViewportScale,
    );

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(r, fillPaint);
    canvas.drawRect(r, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _DrawPreviewPainter oldDelegate) {
    return oldDelegate.drawRect != drawRect ||
        oldDelegate.contentToViewport != contentToViewport ||
        oldDelegate.contentToViewportScale != contentToViewportScale ||
        oldDelegate.color != color;
  }
}

/// Pulsing search icon animation shown while text indexing is in progress.
class _IndexingAnimation extends StatefulWidget {
  final Color color;
  const _IndexingAnimation({required this.color});

  @override
  State<_IndexingAnimation> createState() => _IndexingAnimationState();
}

class _IndexingAnimationState extends State<_IndexingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Icon(
          Icons.search_rounded,
          size: 20,
          color: widget.color.withValues(
            alpha: 0.4 + _scaleAnimation.value * 0.3,
          ),
        );
      },
    );
  }
}
