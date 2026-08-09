// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:pdfrx/pdfrx.dart';

/// Status of search for the current document.
enum IndexStatus {
  /// No document attached to the search provider yet.
  notIndexed,

  /// A search scan is actively running.
  indexing,

  /// Search is idle and the attached document produced (or could produce)
  /// results.
  ready,

  /// The document contains no searchable text (image-only / scanned).
  noText,

  /// Search is disabled for this document (e.g. too many pages).
  /// See [SearchProvider.searchUnavailableReason].
  unavailable,

  /// Search could not be run due to an unexpected error.
  error,
}

/// A single search result produced by [SearchProvider].
class SearchResult {
  final int pageNumber;
  final int charOffset;
  final int length;

  const SearchResult({
    required this.pageNumber,
    required this.charOffset,
    required this.length,
  });
}

/// Query-scoped PDF search that never forces the entire document to load.
///
/// Unlike pdfrx's structured-text search (and the previous custom indexer),
/// this path:
/// - never calls [PdfDocument.loadPagesProgressively] — it only scans pages
///   the viewer has already loaded, so the single shared PDFium worker is
///   not flooded with a full-document page load;
/// - extracts raw text with [PdfPage.loadText] but immediately discards the
///   per-character `charRects` payload for every page except the active
///   match page, keeping main-isolate allocations bounded;
/// - caps per-page text before any lowercasing/indexOf work;
/// - refuses to scan very large documents (> [kMaxTotalPages] pages) and
///   image-only documents, surfacing a human-readable reason instead.
///
/// This keeps large, image-heavy PDFs below Android's ANR and memory
/// thresholds while the search bar itself always opens as a pure-UI action.
class SearchProvider extends ChangeNotifier {
  /// Documents with more pages than this are never scanned. Scanning them
  /// would push the single shared PDFium worker and the main isolate past
  /// Android's ANR/memory thresholds on image-heavy files.
  static const int kMaxTotalPages = 300;

  /// The scan stops after scanning this many loaded pages to bound CPU work
  /// on huge-but-not-disabled documents.
  static const int kMaxScannedPages = 400;

  /// Per-page raw-text cap applied before any lowercasing/indexOf work, so
  /// a single pathological page cannot allocate an unbounded text copy.
  static const int kMaxPageTextChars = 256 * 1024;

  /// Pages sampled (from the already-loaded ones) for the image-only gate.
  static const int kImageOnlySamplePages = 3;

  PdfViewerController? _controller;
  bool _disposed = false;
  bool _attached = false;
  bool _isSearching = false;
  bool _showSearchBar = false;
  String _query = '';
  Timer? _searchDebounce;
  int _searchSession = 0;
  List<SearchResult> _matches = const [];
  int _currentMatchIndex = -1;
  final Map<int, List<PdfRect>> _geometry = {};
  String? _searchUnavailableReason;
  bool _noText = false;
  bool _searchTruncated = false;

  // --- Storm diagnostics (remove once the search-toggle ANR is fixed) ---
  /// Set false to compile out all storm-trace logging/counters.
  static const bool kTraceSearchStorm = true;

  /// Incremented by [ViewerScreen.build] during a trace window.
  static int stormBuildCount = 0;

  /// Incremented by [paintSearchMatches] (every call, incl. no-ops) during a
  /// trace window. Counts page-paint invocations on pdfrx's canvas.
  static int stormPaintCount = 0;

  bool _stormTracePending = false;

  void _maybeStartStormTrace() {
    if (!kTraceSearchStorm || _stormTracePending) return;
    _stormTracePending = true;
    stormBuildCount = 0;
    stormPaintCount = 0;
    debugPrint(
      'STORM: trace armed (search toggle); '
      'semanticsEnabled=${SemanticsBinding.instance.semanticsEnabled}',
    );
    Timer(const Duration(seconds: 12), () {
      debugPrint(
        'STORM: 12s window result — '
        'viewerBuilds=$stormBuildCount pagePaints=$stormPaintCount '
        'semanticsNow=${SemanticsBinding.instance.semanticsEnabled}',
      );
      _stormTracePending = false;
    });
  }

  IndexStatus get indexStatus {
    if (!_attached) return IndexStatus.notIndexed;
    if (_noText) return IndexStatus.noText;
    if (_searchUnavailableReason != null) return IndexStatus.unavailable;
    return _isSearching ? IndexStatus.indexing : IndexStatus.ready;
  }

  String? get errorMessage => null;
  bool get isIndexed => _attached;
  bool get isIndexing => _isSearching;
  bool get hasText => _attached;
  bool get showSearchBar => _showSearchBar;
  int get matchCount => _matches.length;
  int get currentMatchIndex => _currentMatchIndex;
  List<SearchResult> get matches => _matches;
  bool get isAttached => _attached;
  String get query => _query;

  /// Non-null when search cannot run for the attached document
  /// (very large or image-only). Shown in the search bar.
  String? get searchUnavailableReason => _searchUnavailableReason;

  /// True when the scan stopped early at [kMaxScannedPages] and only a
  /// prefix of the document was searched.
  bool get searchTruncated => _searchTruncated;

  void attach(PdfViewerController controller) {
    _controller = controller;
    _attached = true;
    _clearSearchState();
    notifyListeners();
  }

  void detach() {
    _cancelSearch();
    _controller = null;
    _attached = false;
    _clearSearchState();
    notifyListeners();
  }

  /// Pure UI action: opens/closes the search bar. Performs no PDFium or
  /// text operation, so it is always safe even while the document is still
  /// loading or a previous search is being cancelled.
  void toggleSearchBar() {
    _showSearchBar = !_showSearchBar;
    if (!_showSearchBar) {
      clearSearch();
    } else {
      // Arm the storm trace on every open so the next device run reveals
      // whether ViewerScreen.build / page paints fire during the window.
      _maybeStartStormTrace();
    }
    notifyListeners();
  }

  void openSearchBar() {
    _showSearchBar = true;
    notifyListeners();
  }

  void closeSearchBar() {
    _showSearchBar = false;
    clearSearch();
  }

  /// Debounce typing so one large-document scan cannot be started per key.
  void search(String query) {
    if (_disposed) return;
    _query = query;
    _cancelSearch();
    _matches = const [];
    _currentMatchIndex = -1;
    _geometry.clear();
    _searchUnavailableReason = null;
    _noText = false;
    _searchTruncated = false;

    if (query.trim().isEmpty || !_attached) {
      notifyListeners();
      return;
    }

    final session = _searchSession;
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_runSearch(query, session));
    });
    notifyListeners();
  }

  Future<void> _runSearch(String query, int session) async {
    final controller = _controller;
    if (controller == null || !_attached || !_isCurrent(session)) return;

    _isSearching = true;
    notifyListeners();
    try {
      await controller.useDocument((document) async {
        final totalPages = document.pages.length;

        if (totalPages == 0) {
          if (_isCurrent(session)) _noText = true;
          return;
        }

        // Hard gate: never scan very large documents. Scanning would flood
        // the shared PDFium worker and the main isolate with per-character
        // geometry for every page.
        if (totalPages > kMaxTotalPages) {
          if (_isCurrent(session)) {
            _searchUnavailableReason =
                'Search is unavailable for very large documents';
          }
          return;
        }

        // Image-only detection: sample the lowest-numbered already-loaded
        // pages. If every sampled page has no text, stop immediately
        // instead of walking the document extracting nothing.
        if (await _detectImageOnly(document, session)) {
          if (_isCurrent(session)) {
            _searchUnavailableReason =
                'No searchable text found (image-only document)';
          }
          return;
        }

        var scannedPages = 0;
        for (var i = 0; i < totalPages; i++) {
          if (!_isCurrent(session)) return;
          final page = document.pages[i];
          // Only scan pages the viewer has already loaded; never force the
          // whole document to load. Unloaded pages are simply skipped.
          if (!page.isLoaded) continue;

          scannedPages++;
          if (scannedPages > kMaxScannedPages) {
            if (_isCurrent(session)) _searchTruncated = true;
            break;
          }

          final rawText = await _safeLoadText(page);

          // Stale check immediately after the await and BEFORE touching the
          // payload: a superseded session must never allocate or copy the
          // huge charRects list on the main isolate.
          if (!_isCurrent(session)) return;
          if (rawText != null && rawText.fullText.isNotEmpty) {
            _addPageMatches(page.pageNumber, rawText, query);
          }

          // Strict pacing: yield to the UI/raster thread and to the
          // viewer's own rendering (which shares the PDFium worker)
          // between pages.
          notifyListeners();
          await Future<void>.delayed(const Duration(milliseconds: 16));
          if (scannedPages % 8 == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      });
    } catch (e) {
      if (_isCurrent(session)) {
        debugPrint('SearchProvider: search failed: $e');
      }
    } finally {
      if (_isCurrent(session)) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  /// Returns true when the document looks image-only: at least one
  /// already-loaded page was sampled and every sampled page has no text.
  Future<bool> _detectImageOnly(PdfDocument document, int session) async {
    var sampled = 0;
    for (final page in document.pages) {
      if (!page.isLoaded) continue;
      sampled++;
      final rawText = await _safeLoadText(page);
      if (!_isCurrent(session)) return true; // search cancelled — stop scan
      if (rawText != null && rawText.fullText.trim().isNotEmpty) return false;
      if (sampled >= kImageOnlySamplePages) break;
    }
    return sampled > 0;
  }

  Future<PdfPageRawText?> _safeLoadText(PdfPage page) async {
    try {
      return await page.loadText();
    } on RangeError catch (e) {
      debugPrint('SearchProvider: page ${page.pageNumber} RangeError: $e');
      return null;
    } catch (e) {
      debugPrint('SearchProvider: page ${page.pageNumber} failed: $e');
      return null;
    }
  }

  /// Substring scan for one page. Intentionally does NOT retain
  /// [PdfPageRawText.charRects] — geometry is loaded on demand for the
  /// active match page only (see [_ensurePageGeometry]).
  void _addPageMatches(int pageNumber, PdfPageRawText rawText, String query) {
    var text = rawText.fullText;
    if (text.length > kMaxPageTextChars) {
      text = text.substring(0, kMaxPageTextChars);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (lowerQuery.isEmpty) return;

    final pageMatches = <SearchResult>[];
    var offset = 0;
    while (true) {
      final found = lowerText.indexOf(lowerQuery, offset);
      if (found == -1) break;
      pageMatches.add(
        SearchResult(
          pageNumber: pageNumber,
          charOffset: found,
          length: query.length,
        ),
      );
      offset = found + 1;
    }

    if (pageMatches.isEmpty) return;
    _matches = List.unmodifiable([..._matches, ...pageMatches]);
    if (_currentMatchIndex < 0) {
      _currentMatchIndex = 0;
      _goToCurrentMatch();
    }
  }

  void nextMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex = (_currentMatchIndex + 1) % _matches.length;
    _goToCurrentMatch();
    notifyListeners();
  }

  void previousMatch() {
    if (_matches.isEmpty) return;
    _currentMatchIndex =
        (_currentMatchIndex - 1 + _matches.length) % _matches.length;
    _goToCurrentMatch();
    notifyListeners();
  }

  void goToCurrentMatch() => _goToCurrentMatch();

  void _goToCurrentMatch() {
    if (_currentMatchIndex < 0 || _currentMatchIndex >= _matches.length) {
      return;
    }
    final match = _matches[_currentMatchIndex];
    _controller?.goToPage(pageNumber: match.pageNumber);
    unawaited(_ensurePageGeometry(match.pageNumber));
  }

  /// Load geometry only for the active match page. Bounded to a single page
  /// so a huge scanned page's per-character rects cannot accumulate.
  Future<void> _ensurePageGeometry(int pageNumber) async {
    if (_geometry.containsKey(pageNumber)) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.useDocument((document) async {
        if (pageNumber < 1 || pageNumber > document.pages.length) return;
        final page = await document.pages[pageNumber - 1].waitForLoaded(
          timeout: const Duration(seconds: 5),
        );
        if (page == null) return;
        final rawText = await page.loadText();
        if (rawText == null) return;
        _geometry.removeWhere((k, _) => k != pageNumber);
        _geometry[pageNumber] = rawText.charRects;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('SearchProvider: geometry load failed: $e');
    }
  }

  void paintSearchMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    if (kTraceSearchStorm) stormPaintCount++;
    if (_matches.isEmpty) return;
    final rects = _geometry[page.pageNumber];
    if (rects == null) return;

    const matchColor = Color.fromARGB(80, 255, 255, 0);
    const activeColor = Color.fromARGB(120, 255, 200, 0);
    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      if (match.pageNumber != page.pageNumber) continue;
      final end = (match.charOffset + match.length).clamp(0, rects.length);
      if (match.charOffset >= end) continue;
      final paint = Paint()
        ..color = i == _currentMatchIndex ? activeColor : matchColor
        ..style = PaintingStyle.fill;
      for (final rect in rects.sublist(match.charOffset, end)) {
        canvas.drawRect(
          rect.toRectInDocument(page: page, pageRect: pageRect),
          paint,
        );
      }
    }
  }

  void clearSearch() {
    _cancelSearch();
    _query = '';
    _clearSearchState();
    notifyListeners();
  }

  void _clearSearchState() {
    _isSearching = false;
    _matches = const [];
    _currentMatchIndex = -1;
    _geometry.clear();
    _searchUnavailableReason = null;
    _noText = false;
    _searchTruncated = false;
  }

  void _cancelSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchSession++;
  }

  bool _isCurrent(int session) =>
      !_disposed && _attached && session == _searchSession;

  @override
  void dispose() {
    _disposed = true;
    _cancelSearch();
    _controller = null;
    super.dispose();
  }
}
