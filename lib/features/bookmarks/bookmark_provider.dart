import 'package:flutter/material.dart';
import 'package:feya_pdf/features/bookmarks/bookmark.dart';
import 'package:feya_pdf/features/bookmarks/bookmark_service.dart';

/// Manages bookmarks for PDF documents.
///
/// Provides CRUD operations backed by [BookmarkService].
class BookmarkProvider extends ChangeNotifier {
  final BookmarkService _service;

  BookmarkProvider(this._service) {
    _loadAll();
  }

  /// All bookmarks across all files.
  List<Bookmark> _bookmarks = const [];

  /// Bookmarks for the currently active file.
  List<Bookmark> _fileBookmarks = const [];

  /// Currently open file path.
  String? _currentFilePath;

  /// Whether to show the bookmarks panel.
  bool _showPanel = false;

  // ---- Getters ----

  List<Bookmark> get allBookmarks => _bookmarks;

  List<Bookmark> get fileBookmarks => _fileBookmarks;

  bool get showPanel => _showPanel;

  int get bookmarkCount => _fileBookmarks.length;

  // ---- File lifecycle ----

  /// Set the currently open file and load its bookmarks.
  void openFile(String filePath) {
    _currentFilePath = filePath;
    _fileBookmarks = _bookmarks.where((b) => b.filePath == filePath).toList();
    notifyListeners();
  }

  /// Close the current file (clear file-specific state).
  void closeFile() {
    _currentFilePath = null;
    _fileBookmarks = const [];
    _showPanel = false;
    notifyListeners();
  }

  // ---- CRUD ----

  /// Add a new bookmark.
  Future<void> addBookmark(Bookmark bookmark) async {
    _bookmarks = [..._bookmarks, bookmark];
    if (bookmark.filePath == _currentFilePath) {
      _fileBookmarks = [..._fileBookmarks, bookmark];
    }
    await _service.saveForFile(
      bookmark.filePath,
      _bookmarks.where((b) => b.filePath == bookmark.filePath).toList(),
    );
    notifyListeners();
  }

  /// Rename a bookmark by ID.
  Future<void> renameBookmark(String id, String newLabel) async {
    final idx = _bookmarks.indexWhere((b) => b.id == id);
    if (idx == -1) return;
    final updated = _bookmarks[idx].copyWith(label: newLabel);
    _bookmarks = [..._bookmarks];
    _bookmarks[idx] = updated;
    if (_currentFilePath != null) {
      _fileBookmarks =
          _bookmarks.where((b) => b.filePath == _currentFilePath).toList();
    }
    await _service.saveForFile(
      updated.filePath,
      _bookmarks.where((b) => b.filePath == updated.filePath).toList(),
    );
    notifyListeners();
  }

  /// Remove a bookmark by ID.
  Future<void> removeBookmark(String id) async {
    _bookmarks = _bookmarks.where((b) => b.id != id).toList();
    if (_currentFilePath != null) {
      _fileBookmarks =
          _bookmarks.where((b) => b.filePath == _currentFilePath).toList();
    }
    await _service.deleteBookmark(id);
    notifyListeners();
  }

  /// Check if a specific page is bookmarked in the current file.
  bool isPageBookmarked(int pageNumber) =>
      _fileBookmarks.any((b) => b.pageNumber == pageNumber);

  /// Remove all bookmarks associated with a given file path.
  Future<void> forgetFile(String filePath) async {
    _bookmarks = _bookmarks.where((b) => b.filePath != filePath).toList();
    if (_currentFilePath == filePath) {
      _fileBookmarks = const [];
    }
    await _service.saveForFile(filePath, []);
    notifyListeners();
  }

  /// Update the file path for all bookmarks matching [oldPath] to [newPath].
  Future<void> renameFile(String oldPath, String newPath) async {
    var changed = false;
    _bookmarks = _bookmarks.map((b) {
      if (b.filePath == oldPath) {
        changed = true;
        return b.copyWith(filePath: newPath);
      }
      return b;
    }).toList();
    if (!changed) return;
    if (_currentFilePath == oldPath) {
      _currentFilePath = newPath;
      _fileBookmarks =
          _bookmarks.where((b) => b.filePath == newPath).toList();
    }
    // Save old-path bookmarks as empty, new-path with migrated bookmarks
    await _service.saveForFile(oldPath, []);
    await _service.saveForFile(
      newPath,
      _bookmarks.where((b) => b.filePath == newPath).toList(),
    );
    notifyListeners();
  }

  // ---- Panel toggling ----

  void togglePanel() {
    _showPanel = !_showPanel;
    notifyListeners();
  }

  void setShowPanel(bool value) {
    if (_showPanel == value) return;
    _showPanel = value;
    notifyListeners();
  }

  // ---- Internal ----

  void _loadAll() {
    _bookmarks = _service.loadAll();
  }

  /// Reload from persistent storage.
  Future<void> reload() async {
    _loadAll();
    if (_currentFilePath != null) {
      _fileBookmarks =
          _bookmarks.where((b) => b.filePath == _currentFilePath).toList();
    }
    notifyListeners();
  }
}
