// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/features/tags/tag.dart';

/// SharedPreferences-backed persistence for tags and file→tag mappings.
///
/// Keys:
///   mely_pdf_tags        → JSON list of `Tag` objects
///   mely_pdf_file_tags   → JSON map of filePath → List of tagId
///
/// File paths are absolute paths, so they survive encryption (the same
/// path is used for both .pdf and .pdf.enc) and can be re-resolved by the
/// file scanner on next launch.
class TagService {
  static const _kTags = 'mely_pdf_tags';
  static const _kFileTags = 'mely_pdf_file_tags';

  final SharedPreferences _prefs;

  TagService(this._prefs);

  // --- Tags ---

  /// Load all tags, or empty list if none stored or data is corrupt.
  List<Tag> getAllTags() {
    final raw = _prefs.getString(_kTags);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Tag.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persist the full tag list. Replaces any existing data.
  Future<void> saveTags(List<Tag> tags) async {
    final encoded = jsonEncode(tags.map((t) => t.toJson()).toList());
    await _prefs.setString(_kTags, encoded);
  }

  // --- File → tags mapping ---

  /// Load the file→tagIds map, or empty map if none stored.
  Map<String, List<String>> getFileTagMap() {
    final raw = _prefs.getString(_kFileTags);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, List<String>>{};
      decoded.forEach((key, value) {
        if (key is String && value is List) {
          result[key] = value.whereType<String>().toList();
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Persist the file→tagIds map. Replaces any existing data.
  Future<void> saveFileTagMap(Map<String, List<String>> map) async {
    final encoded = jsonEncode(
      map.map((k, v) => MapEntry(k, List<String>.from(v))),
    );
    await _prefs.setString(_kFileTags, encoded);
  }
}
