import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A full-screen bottom sheet that shows page thumbnails in a 3-4 column grid.
/// Tapping a thumbnail jumps to that page via [onPageSelected].
///
/// Thumbnails are rendered lazily (only visible ones) and cached in memory
/// to avoid re-rendering pages that have already been fetched.
class ThumbnailGrid extends StatefulWidget {
  final PdfDocumentRef documentRef;
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  const ThumbnailGrid({
    super.key,
    required this.documentRef,
    required this.currentPage,
    required this.onPageSelected,
  });

  /// Show the thumbnail grid as a modal bottom sheet.
  static void show(
    BuildContext context, {
    required PdfDocumentRef documentRef,
    required int currentPage,
    required ValueChanged<int> onPageSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ThumbnailGrid(
        documentRef: documentRef,
        currentPage: currentPage,
        onPageSelected: onPageSelected,
      ),
    );
  }

  @override
  State<ThumbnailGrid> createState() => _ThumbnailGridState();
}

class _ThumbnailGridState extends State<ThumbnailGrid> {
  /// In-memory cache of rendered thumbnails: pageIndex -> ui.Image
  final Map<int, ui.Image> _cache = {};

  /// Tracks which pages are currently being rendered (to avoid duplicate work)
  final Set<int> _pending = {};

  /// Grid scroll controller — set once the bottom sheet's builder provides it.
  ScrollController? _scrollController;

  PdfDocument? get _document =>
      widget.documentRef.resolveListenable().document;

  /// Resolution at which pages are rendered (independent of display size).
  static const int _renderWidth = 160;

  /// Default aspect ratio fallback (A4 portrait ≈ 595/842).
  /// Used for scroll estimation and grid sizing before real page dims are known.
  static const double _defaultAspectRatio = 595.0 / 842.0;

  /// Returns the actual page aspect ratio (width / height) from the document.
  /// Falls back to [_defaultAspectRatio] if the document or page is unavailable.
  double _getPageAspectRatio(PdfDocument doc, int pageIndex) {
    if (pageIndex < 0 || pageIndex >= doc.pages.length) {
      return _defaultAspectRatio;
    }
    final page = doc.pages[pageIndex];
    final ratio = page.width / page.height;
    // Guard against degenerate dimensions (shouldn't happen with real PDFs).
    return ratio > 0 ? ratio : _defaultAspectRatio;
  }

  @override
  void dispose() {
    _scrollController?.removeListener(_onScroll);
    for (final image in _cache.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ThumbnailGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentRef != widget.documentRef) {
      for (final image in _cache.values) {
        image.dispose();
      }
      _cache.clear();
      _pending.clear();
    }
  }

  /// Returns 3 columns on phones, 4 on tablets/landscape.
  int _columnCount(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide >= 600 ? 4 : 3;
  }

  /// Convert a [PdfImage] (BGRA8888) to a [ui.Image] for display.
  Future<ui.Image> _convertToUiImage(PdfImage pdfImage) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pdfImage.pixels,
      pdfImage.width,
      pdfImage.height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Render a single page thumbnail and cache it.
  Future<void> _renderPage(int pageIndex) async {
    final doc = _document;
    if (doc == null || pageIndex < 0 || pageIndex >= doc.pages.length) return;
    if (_cache.containsKey(pageIndex) || _pending.contains(pageIndex)) return;

    _pending.add(pageIndex);
    if (mounted) setState(() {});

    try {
      final page = doc.pages[pageIndex];
      final pdfImage = await page.render(width: _renderWidth);
      if (pdfImage == null || !mounted) {
        pdfImage?.dispose();
        if (mounted) setState(() => _pending.remove(pageIndex));
        return;
      }

      final uiImage = await _convertToUiImage(pdfImage);
      pdfImage.dispose();

      if (mounted) {
        setState(() {
          _cache[pageIndex] = uiImage;
          _pending.remove(pageIndex);
        });
      } else {
        uiImage.dispose();
        _pending.remove(pageIndex);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _pending.remove(pageIndex));
      } else {
        _pending.remove(pageIndex);
      }
    }
  }

  /// Trigger rendering for a range of page indices.
  void _renderRange(int first, int last) {
    final doc = _document;
    if (doc == null) return;
    final count = doc.pages.length;
    final start = first.clamp(0, count - 1);
    final end = last.clamp(0, count - 1);
    for (var i = start; i <= end; i++) {
      _renderPage(i);
    }
  }

  /// Estimate the number of grid columns for scroll calculations.
  /// Must align with the actual [SliverGridDelegateWithFixedCrossAxisCount]
  /// used in the build method.
  int _estimateColumnCount() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return 3;
    // Use the viewport width to estimate columns
    final viewportWidth = controller.position.viewportDimension;
    return viewportWidth >= 600 ? 4 : 3;
  }

  /// Estimate the row height (cell height + mainAxisSpacing) for scroll
  /// offset calculations.
  ///
  /// Uses [_defaultAspectRatio] for estimation since individual page ratios
  /// aren't known at scroll-offset-prediction time. The estimate is
  /// approximate and fine for scroll triggering purposes.
  double _estimateRowExtent() {
    const spacing = 12.0;
    const padding = 24.0; // 12dp left + 12dp right
    final cols = _estimateColumnCount();

    final controller = _scrollController;
    final availWidth =
        (controller?.hasClients == true)
            ? controller!.position.viewportDimension - padding
            : 360.0;

    final cellWidth = (availWidth - (cols - 1) * spacing) / cols;
    // Label area: 6dp gap + ~16dp text height = ~22dp
    const labelHeight = 22.0;
    final cellHeight = cellWidth / _defaultAspectRatio + labelHeight;
    return cellHeight + spacing;
  }

  /// Called when the user scrolls — renders pages in the visible viewport
  /// plus a buffer zone.
  void _onScroll() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;

    final doc = _document;
    if (doc == null) return;
    final count = doc.pages.length;
    if (count == 0) return;

    final cols = _estimateColumnCount();
    if (cols == 0) return;
    final rowExtent = _estimateRowExtent();
    if (rowExtent <= 0) return;

    final viewportHeight = controller.position.viewportDimension;
    final itemsPerViewport =
        ((viewportHeight / rowExtent).ceil()) * cols;

    final firstRow = (controller.offset / rowExtent).floor();
    final firstVisible = firstRow * cols;
    final lastVisible = firstVisible + itemsPerViewport;

    const buffer = 10; // ~1.5 extra rows in 3-col, ~2.5 in 4-col
    _renderRange(
      (firstVisible - buffer).clamp(0, count - 1),
      (lastVisible + buffer).clamp(0, count - 1),
    );
  }

  void _setScrollController(ScrollController controller) {
    _scrollController?.removeListener(_onScroll);
    _scrollController = controller;
    _scrollController!.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colCount = _columnCount(context);

    // Grid spacing constants
    const crossAxisSpacing = 12.0;
    const mainAxisSpacing = 12.0;
    const labelAreaHeight = 22.0; // 6dp gap + ~16dp text

    // Compute aspect ratio for the grid child so it maps to:
    //   cell width  -> (cell width / defaultAspectRatio + label)
    // We use the actual screen / sheet width as a good approximation.
    // Individual tiles use their own actual page aspect ratio internally.
    const padding = 24.0; // 12dp left + 12dp right
    final availWidth = MediaQuery.of(context).size.width - padding;
    final cellWidth = (availWidth - (colCount - 1) * crossAxisSpacing) / colCount;
    final cellHeight = cellWidth / _defaultAspectRatio + labelAreaHeight;
    final childAspectRatio = cellWidth / cellHeight;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        _setScrollController(scrollController);

        final doc = _document;
        final pageCount = doc?.pages.length ?? 0;

        return Column(
          children: [
            // Handle bar
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thumbnails',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$pageCount pages',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            // Grid
            Expanded(
              child: pageCount == 0
                  ? Center(
                      child: Text(
                        'No pages available',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: colCount,
                        mainAxisSpacing: mainAxisSpacing,
                        crossAxisSpacing: crossAxisSpacing,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemCount: pageCount,
                      itemBuilder: (context, index) {
                        final isCurrentPage = index + 1 == widget.currentPage;
                        final realRatio = doc != null
                            ? _getPageAspectRatio(doc, index)
                            : _defaultAspectRatio;
                        return _ThumbnailTile(
                          pageIndex: index,
                          image: _cache[index],
                          isCurrentPage: isCurrentPage,
                          isLoading: _pending.contains(index),
                          pageAspectRatio: realRatio,
                          onTap: () {
                            widget.onPageSelected(index + 1);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ThumbnailTile extends StatelessWidget {
  final int pageIndex;
  final ui.Image? image;
  final bool isCurrentPage;
  final bool isLoading;
  final double pageAspectRatio;
  final VoidCallback onTap;

  const _ThumbnailTile({
    required this.pageIndex,
    required this.image,
    required this.isCurrentPage,
    required this.isLoading,
    required this.pageAspectRatio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnail preview - uses AspectRatio to fill grid cell width
          // while maintaining the page's w/h ratio
          AspectRatio(
            aspectRatio: pageAspectRatio,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCurrentPage
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: isCurrentPage ? 2.5 : 1.0,
                ),
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildPreview(colorScheme),
            ),
          ),
          const SizedBox(height: 6),
          // Page number label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isCurrentPage
                  ? colorScheme.primary.withValues(alpha: 0.1)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${pageIndex + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isCurrentPage ? FontWeight.w600 : FontWeight.w400,
                color: isCurrentPage
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ColorScheme colorScheme) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      );
    }

    if (image != null) {
      return RawImage(
        image: image,
        fit: BoxFit.contain,
        isAntiAlias: true,
      );
    }

    // Placeholder for pages not yet rendered
    return Center(
      child: Icon(
        Icons.auto_stories_rounded,
        size: 32,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    );
  }
}
