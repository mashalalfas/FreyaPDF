import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/features/bookmarks/bookmark.dart';

/// Persists [Bookmark] per PDF file using SharedPreferences.
///
/// Data layout:
///   key = 'freya_pdf_bookmarks' => JSON map { filePath -> [bookmarkJSON, ...] }
class BookmarkService {
  static const _kBookmarks = 'freya_pdf_bookmarks';

  final SharedPreferences _prefs;

  BookmarkService(this._prefs);

  /// Load all bookmarks from storage.
  List<Bookmark> loadAll() {
    final raw = _prefs.getString(_kBookmarks);
    if (raw == null) return const [];
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final results = <Bookmark>[];
      for (final entry in map.entries) {
        final filePath = entry.key;
        final list = (entry.value as List)
            .cast<Map<String, dynamic>>()
            .map((j) => Bookmark.fromJson(j));
        // Ensure filePath in the JSON matches the key (data integrity)
        results.addAll(list.map((b) {
          if (b.filePath != filePath) {
            return Bookmark(
              id: b.id,
              filePath: filePath,
              pageNumber: b.pageNumber,
              label: b.label,
              createdAt: b.createdAt,
            );
          }
          return b;
        }));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Load bookmarks for a specific file.
  List<Bookmark> loadForFile(String filePath) {
    return loadAll().where((b) => b.filePath == filePath).toList();
  }

  /// Save a complete list of bookmarks for a specific file, preserving others.
  Future<void> saveForFile(String filePath, List<Bookmark> bookmarks) async {
    final raw = _prefs.getString(_kBookmarks);
    final Map<String, dynamic> map = _decodeBookmarksMap(raw);
    map[filePath] = bookmarks.map((b) => b.toJson()).toList();
    await _prefs.setString(_kBookmarks, jsonEncode(map));
  }

  /// Delete a bookmark by ID.
  Future<void> deleteBookmark(String id) async {
    final all = loadAll();
    final idx = all.indexWhere((b) => b.id == id);
    if (idx == -1) return;
    final target = all[idx];
    final filePath = target.filePath;
    final filtered = all.where((b) => b.id != id).toList();
    await saveForFile(
      filePath,
      filtered.where((b) => b.filePath == filePath).toList(),
    );
  }

  /// Safely decode the bookmarks JSON map.
  Map<String, dynamic> _decodeBookmarksMap(String? raw) {
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
