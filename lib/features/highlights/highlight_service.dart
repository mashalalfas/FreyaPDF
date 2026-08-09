import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/features/highlights/highlight.dart';

/// Persists [HighlightData] per PDF file using SharedPreferences.
///
/// Data layout (v2):
///   key = 'freya_pdf_highlights' => JSON map { filePath -> [highlightJSON, ...] }
class HighlightService {
  static const _kHighlights = 'freya_pdf_highlights';

  final SharedPreferences _prefs;

  HighlightService(this._prefs);

  /// Load all highlights from storage.
  List<HighlightData> loadAll() {
    final raw = _prefs.getString(_kHighlights);
    if (raw == null) return const [];
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final results = <HighlightData>[];
      for (final entry in map.entries) {
        final filePath = entry.key;
        final list = (entry.value as List)
            .cast<Map<String, dynamic>>()
            .map((j) => HighlightData.fromJson(j));
        // Ensure filePath in the JSON matches the key (data integrity)
        results.addAll(list.map((h) {
          if (h.filePath != filePath) {
            return HighlightData(
              id: h.id,
              filePath: filePath,
              pageNumber: h.pageNumber,
              text: h.text,
              color: h.color,
              createdAt: h.createdAt,
            );
          }
          return h;
        }));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Load highlights for a specific file.
  List<HighlightData> loadForFile(String filePath) {
    return loadAll().where((h) => h.filePath == filePath).toList();
  }

  /// Save a complete list of highlights for a specific file, preserving others.
  Future<void> saveForFile(String filePath, List<HighlightData> highlights) async {
    final raw = _prefs.getString(_kHighlights);
    final Map<String, dynamic> map = _decodeHighlightsMap(raw);
    map[filePath] = highlights.map((h) => h.toJson()).toList();
    await _prefs.setString(_kHighlights, jsonEncode(map));
  }

  /// Delete a highlight by ID.
  Future<void> deleteHighlight(String id) async {
    final all = loadAll();
    final idx = all.indexWhere((h) => h.id == id);
    if (idx == -1) return;
    final target = all[idx];
    final filePath = target.filePath;
    final filtered = all.where((h) => h.id != id).toList();
    await saveForFile(
      filePath,
      filtered.where((h) => h.filePath == filePath).toList(),
    );
  }

  /// Safely decode the highlights JSON map.
  Map<String, dynamic> _decodeHighlightsMap(String? raw) {
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
