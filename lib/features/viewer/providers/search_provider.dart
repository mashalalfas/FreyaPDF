import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A ChangeNotifier that bridges the search bar UI callbacks with pdfrx's
/// built-in [PdfTextSearcher] for text search, match navigation, and
/// match highlighting on PDF pages.
class SearchProvider extends ChangeNotifier {
  PdfTextSearcher? _searcher;
  List<PdfPageTextRange> _matches = const [];
  bool _disposed = false;

  /// Whether a search task is currently running.
  bool get isSearching => _searcher?.isSearching ?? false;

  /// The total number of matches found.
  int get matchCount => _matches.length;

  /// The 0-based index of the currently active match.
  int get currentMatchIndex => _searcher?.currentIndex ?? 0;

  /// All matches found by the current search.
  List<PdfPageTextRange> get matches => _matches;

  /// Attach to a [PdfViewerController] to enable searching.
  ///
  /// Call this once the PDF viewer controller is ready (e.g. in
  /// [PdfViewerParams.onViewerReady]).
  void attach(PdfViewerController controller) {
    detach();
    try {
      _searcher = PdfTextSearcher(controller);
      _searcher!.addListener(_onSearcherChanged);
    } catch (e) {
      debugPrint('SearchProvider.attach error: $e');
      _searcher = null;
    }
  }

  /// Detach from the controller and release resources.
  void detach() {
    _searcher?.removeListener(_onSearcherChanged);
    _searcher?.dispose();
    _searcher = null;
    _matches = const [];
    notifyListeners();
  }

  void _onSearcherChanged() {
    if (_disposed) return;
    _matches = _searcher?.matches ?? const [];
    notifyListeners();
  }

  /// Start searching for [query] within the PDF document.
  ///
  /// If [query] is empty, the current search is cleared.
  void search(String query) {
    if (_disposed) return;
    if (query.isEmpty) {
      _searcher?.resetTextSearch();
      _matches = const [];
      notifyListeners();
      return;
    }
    try {
      _searcher?.startTextSearch(
        query,
        goToFirstMatch: true,
        searchImmediately: true,
      );
    } catch (e) {
      // Safeguard against pdfrx PdfTextSearcher internal errors
      // (e.g. accessing a disposed document).
      debugPrint('PdfTextSearcher.startTextSearch error: $e');
      _matches = const [];
      _onSearcherChanged();
    }
  }

  /// Navigate to the next match in the results.
  Future<void> nextMatch() async {
    if (_disposed) return;
    try {
      await _searcher?.goToNextMatch();
    } catch (e) {
      debugPrint('PdfTextSearcher.goToNextMatch error: $e');
    }
  }

  /// Navigate to the previous match in the results.
  Future<void> previousMatch() async {
    if (_disposed) return;
    try {
      await _searcher?.goToPrevMatch();
    } catch (e) {
      debugPrint('PdfTextSearcher.goToPrevMatch error: $e');
    }
  }

  /// Clear the current search results and reset the search state.
  void clearSearch() {
    if (_disposed) return;
    try {
      _searcher?.resetTextSearch();
    } catch (e) {
      debugPrint('PdfTextSearcher.resetTextSearch error: $e');
    }
    _matches = const [];
    notifyListeners();
  }

  /// Paint callback to render match highlight rectangles on PDF pages.
  ///
  /// Add this to [PdfViewerParams.pagePaintCallbacks] so that matches are
  /// drawn as overlays on each page. The current (active) match is rendered
  /// in yellow; other matches in light gray.
  void pagePaintCallback(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    _searcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  @override
  void dispose() {
    _disposed = true;
    detach();
    super.dispose();
  }
}
