import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:freya_pdf/features/highlights/highlight.dart';
import 'package:freya_pdf/features/highlights/highlight_service.dart';

/// Manages text and rectangle highlights for PDF documents.
///
/// Provides painting callbacks for rendering highlights on PDF pages,
/// and CRUD operations backed by [HighlightService].
///
/// Supports two highlight modes:
/// - **Text highlight**: long-press text → select → "Highlight" in context menu
/// - **Rectangle draw**: drag to draw a colored rectangle on any page area
class HighlightProvider extends ChangeNotifier {
  final HighlightService _service;

  HighlightProvider(this._service) {
    _loadAll();
  }

  /// All highlights across all files.
  List<HighlightData> _highlights = const [];

  /// Highlights for the currently active file.
  List<HighlightData> _fileHighlights = const [];

  /// Currently open file path.
  String? _currentFilePath;

  /// Highlight mode: 'off', 'text', or 'rectangle'.
  String _highlightMode = 'off';

  /// Whether to show the highlights panel.
  bool _showPanel = false;

  // ---- Rectangle drawing state ----

  /// Start point of the current drag (page coordinates).
  Offset? _drawStart;

  /// Current drag point (page coordinates).
  Offset? _drawCurrent;

  /// The page number being drawn on.
  int? _drawPageNumber;

  // ---- Getters ----

  List<HighlightData> get allHighlights => _highlights;

  List<HighlightData> get fileHighlights => _fileHighlights;

  /// Whether any highlight mode is active.
  bool get highlightMode => _highlightMode != 'off';

  /// The current highlight mode string.
  String get highlightModeValue => _highlightMode;

  /// Whether rectangle draw mode is active.
  bool get isRectangleDrawMode => _highlightMode == 'rectangle';

  bool get showPanel => _showPanel;

  int get highlightCount => _fileHighlights.length;

  /// Current rectangle being drawn (null if not dragging).
  Rect? get drawRect {
    if (_drawStart == null || _drawCurrent == null) return null;
    return Rect.fromPoints(_drawStart!, _drawCurrent!);
  }

  /// The page number currently being drawn on.
  int? get drawPageNumber => _drawPageNumber;

  // ---- File lifecycle ----

  /// Set the currently open file and load its highlights.
  void openFile(String filePath) {
    _currentFilePath = filePath;
    _fileHighlights = _highlights.where((h) => h.filePath == filePath).toList();
    // Reset highlight mode so it doesn't carry over from the previous file.
    _highlightMode = 'off';
    _drawStart = null;
    _drawCurrent = null;
    _drawPageNumber = null;
    notifyListeners();
  }

  /// Close the current file (clear file-specific state).
  void closeFile() {
    _currentFilePath = null;
    _fileHighlights = const [];
    _highlightMode = 'off';
    _showPanel = false;
    _drawStart = null;
    _drawCurrent = null;
    _drawPageNumber = null;
    notifyListeners();
  }

  // ---- CRUD ----

  /// Add a new highlight.
  Future<void> addHighlight(HighlightData highlight) async {
    _highlights = [..._highlights, highlight];
    if (highlight.filePath == _currentFilePath) {
      _fileHighlights = [..._fileHighlights, highlight];
    }
    await _service.saveForFile(
      highlight.filePath,
      _highlights.where((h) => h.filePath == highlight.filePath).toList(),
    );
    notifyListeners();
  }

  /// Remove a highlight by ID.
  Future<void> removeHighlight(String id) async {
    _highlights = _highlights.where((h) => h.id != id).toList();
    if (_currentFilePath != null) {
      _fileHighlights = _highlights
          .where((h) => h.filePath == _currentFilePath)
          .toList();
    }
    await _service.deleteHighlight(id);
    notifyListeners();
  }

  // ---- Mode toggling ----

  /// Toggle highlight mode: off ↔ rectangle (draw).
  /// Text highlight is always available via long-press, no mode needed.
  void toggleHighlightMode() {
    switch (_highlightMode) {
      case 'off':
        _highlightMode = 'rectangle';
        break;
      case 'rectangle':
        _highlightMode = 'off';
        break;
      default:
        _highlightMode = 'off';
    }
    _drawStart = null;
    _drawCurrent = null;
    _drawPageNumber = null;
    notifyListeners();
  }

  void setHighlightMode(String value) {
    if (_highlightMode == value) return;
    _highlightMode = value;
    _drawStart = null;
    _drawCurrent = null;
    _drawPageNumber = null;
    notifyListeners();
  }

  /// Set highlight mode by cycling to a specific value.
  void setHighlightModeBool(bool value) {
    // Legacy compat: true → 'rectangle', false → 'off'
    setHighlightMode(value ? 'rectangle' : 'off');
  }

  void togglePanel() {
    _showPanel = !_showPanel;
    notifyListeners();
  }

  void setShowPanel(bool value) {
    if (_showPanel == value) return;
    _showPanel = value;
    notifyListeners();
  }

  // ---- Rectangle draw operations ----

  /// Start drawing a rectangle at the given page-relative offset.
  void startDraw(Offset position, int pageNumber) {
    _drawStart = position;
    _drawCurrent = position;
    _drawPageNumber = pageNumber;
    notifyListeners();
  }

  /// Update the current drag position.
  void updateDraw(Offset position) {
    if (_drawStart == null) return;
    _drawCurrent = position;
    notifyListeners();
  }

  /// End drawing and create the rectangle highlight.
  Future<void> endDraw() async {
    if (_drawStart == null || _drawCurrent == null || _drawPageNumber == null) {
      _drawStart = null;
      _drawCurrent = null;
      _drawPageNumber = null;
      notifyListeners();
      return;
    }

    final rect = Rect.fromPoints(_drawStart!, _drawCurrent!);
    _drawStart = null;
    _drawCurrent = null;
    final pageNumber = _drawPageNumber!;
    _drawPageNumber = null;

    // Ignore tiny accidental taps (less than 5px in either dimension).
    if (rect.width.abs() < 5 && rect.height.abs() < 5) {
      notifyListeners();
      return;
    }

    if (_currentFilePath == null) return;

    final highlight = HighlightData(
      filePath: _currentFilePath!,
      pageNumber: pageNumber,
      text: '',
      type: 'rectangle',
      rectLeft: rect.left,
      rectTop: rect.top,
      rectRight: rect.right,
      rectBottom: rect.bottom,
    );

    await addHighlight(highlight);

    // Auto-disable draw mode after creating one box — tap again to draw another.
    _highlightMode = 'off';
    notifyListeners();
  }

  /// Cancel the current draw without saving.
  void cancelDraw() {
    _drawStart = null;
    _drawCurrent = null;
    _drawPageNumber = null;
    _highlightMode = 'off';
    notifyListeners();
  }

  // ---- Internal ----

  void _loadAll() {
    _highlights = _service.loadAll();
  }

  /// Reload from persistent storage.
  Future<void> reload() async {
    _loadAll();
    if (_currentFilePath != null) {
      _fileHighlights = _highlights
          .where((h) => h.filePath == _currentFilePath)
          .toList();
    }
    notifyListeners();
  }

  // ---- Paint Callback ----

  /// A map of pageTexts pre-loaded for the current document.
  /// Populated by [cachePageText] for visible pages.
  Map<int, PdfPageText> _pageTextCache = {};

  /// Load structured text only for a visible page. Full-document preloading
  /// makes large image-heavy PDFs compete with rendering and search.
  Future<void> cachePageText(PdfDocument document, int pageNumber) async {
    if (_pageTextCache.containsKey(pageNumber) ||
        pageNumber < 1 ||
        pageNumber > document.pages.length) {
      return;
    }
    try {
      final page = await document.pages[pageNumber - 1].waitForLoaded(
        timeout: const Duration(seconds: 5),
      );
      if (page == null) return;
      final text = await page.loadStructuredText();
      _pageTextCache[pageNumber] = text;
      notifyListeners();
    } catch (e) {
      debugPrint('HighlightProvider: Page $pageNumber failed: $e');
    }
  }

  /// Clear the page text cache.
  void clearPageTextCache() {
    _pageTextCache = {};
  }

  /// Paint callback to render highlights on PDF pages.
  ///
  /// Add this to [PdfViewerParams.pagePaintCallbacks].
  void paintHighlights(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    // Draw existing highlights for this page
    if (_fileHighlights.isNotEmpty) {
      final pageHighlights = _fileHighlights
          .where((h) => h.pageNumber == page.pageNumber)
          .toList();
      if (pageHighlights.isNotEmpty) {
        final pageText = _pageTextCache[page.pageNumber];
        if (pageText != null) {
          for (final highlight in pageHighlights) {
            _paintHighlightOnPage(canvas, pageRect, page, pageText, highlight);
          }
        }
      }
    }

    // Note: The in-progress rectangle preview is drawn by the overlay's
    // _DrawPreviewPainter in viewer_screen.dart, which uses the same
    // widget-space coordinates as the GestureDetector. Drawing it here
    // on the pdfrx canvas as well would cause a double-render (two boxes).
  }

  void _paintHighlightOnPage(
    ui.Canvas canvas,
    Rect pageRect,
    PdfPage page,
    PdfPageText pageText,
    HighlightData highlight,
  ) {
    if (highlight.isRectangle) {
      _paintRectangleHighlight(canvas, pageRect, page, highlight);
    } else {
      _paintTextHighlight(canvas, pageRect, page, pageText, highlight);
    }
  }

  /// Paint a rectangle-type highlight (stored viewer content-space coords).
  ///
  /// Coordinates come from the GestureDetector, converted from viewport-space
  /// to content-space by adding the scroll offset (visibleRect.topLeft).
  /// The pdfrx pagePaintCallback canvas operates in the same content space,
  /// so coords are drawn directly without any translation.
  void _paintRectangleHighlight(
    ui.Canvas canvas,
    Rect pageRect,
    PdfPage page,
    HighlightData highlight,
  ) {
    if (highlight.rectLeft == null ||
        highlight.rectTop == null ||
        highlight.rectRight == null ||
        highlight.rectBottom == null) {
      return;
    }

    final rect = Rect.fromLTRB(
      highlight.rectLeft!,
      highlight.rectTop!,
      highlight.rectRight!,
      highlight.rectBottom!,
    );

    final color = Color(highlight.color);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, borderPaint);
  }

  /// Paint a text-type highlight (search for text on page).
  void _paintTextHighlight(
    ui.Canvas canvas,
    Rect pageRect,
    PdfPage page,
    PdfPageText pageText,
    HighlightData highlight,
  ) {
    final pattern = highlight.text;
    if (pattern.isEmpty) return;

    // Find all occurrences of the highlighted text
    final textStr = pageText.fullText;
    final searchPattern = RegExp.escape(pattern);
    final regex = RegExp(searchPattern, caseSensitive: true);

    // Collect all match rectangles
    final matchRects = <Rect>[];
    for (final match in regex.allMatches(textStr)) {
      if (match.start == match.end) continue;
      final range = PdfPageTextRange(
        pageText: pageText,
        start: match.start,
        end: match.end,
      );
      final pdfRect = range.bounds;
      final widgetRect = pdfRect.toRect(
        page: page,
        scaledPageSize: pageRect.size,
      );
      matchRects.add(widgetRect.translate(pageRect.left, pageRect.top));
    }

    // Draw the highlight rectangles
    final color = Color(highlight.color);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final rect in matchRects) {
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  // ---- Dispose ----

  @override
  void dispose() {
    _pageTextCache = {};
    super.dispose();
  }
}
