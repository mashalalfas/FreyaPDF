// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/foundation.dart';
import 'package:freya_pdf/features/tags/tag.dart';
import 'package:freya_pdf/features/tags/tag_service.dart';

/// State holder for user-defined tags and the active tag filter.
///
/// Source of truth for all tag-related state. Persists to SharedPreferences
/// via [TagService]. UI widgets (HomeScreen filter bar, TagsScreen, file
/// context menu) read and mutate state through this provider.
class TagProvider extends ChangeNotifier {
  final TagService _service;

  List<Tag> _tags = [];
  Map<String, List<String>> _fileTagMap = {};
  String? _activeFilterTagId;

  TagProvider(this._service) {
    _tags = _service.getAllTags();
    _fileTagMap = _service.getFileTagMap();
  }

  // --- Read access ---

  List<Tag> get tags => List.unmodifiable(_tags);

  /// Currently active filter tag, or null when showing all files.
  String? get activeFilterTagId => _activeFilterTagId;

  Tag? get activeFilterTag {
    if (_activeFilterTagId == null) return null;
    for (final t in _tags) {
      if (t.id == _activeFilterTagId) return t;
    }
    return null;
  }

  bool get hasTags => _tags.isNotEmpty;

  /// Returns a copy of the tagIds for [filePath], or an empty list.
  List<String> getTagsForFile(String filePath) {
    final ids = _fileTagMap[filePath];
    if (ids == null) return const [];
    return List<String>.unmodifiable(ids);
  }

  /// Returns the resolved [Tag] objects for [filePath] (in stored order).
  List<Tag> getResolvedTagsForFile(String filePath) {
    final ids = _fileTagMap[filePath];
    if (ids == null || ids.isEmpty) return const [];
    final tagMap = {for (final t in _tags) t.id: t};
    return ids
        .map((id) => tagMap[id])
        .whereType<Tag>()
        .toList(growable: false);
  }

  bool fileHasTag(String filePath, String tagId) {
    return _fileTagMap[filePath]?.contains(tagId) ?? false;
  }

  /// Number of files currently mapped to [tagId].
  int countFilesWithTag(String tagId) {
    var count = 0;
    for (final ids in _fileTagMap.values) {
      if (ids.contains(tagId)) count++;
    }
    return count;
  }

  Tag? tagById(String id) {
    for (final t in _tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  // --- Filter state ---

  /// Set or clear the active tag filter.
  void setActiveFilter(String? tagId) {
    if (_activeFilterTagId == tagId) return;
    _activeFilterTagId = tagId;
    notifyListeners();
  }

  void clearFilter() => setActiveFilter(null);

  // --- Tag CRUD ---

  /// Create a new tag and persist. Returns the new tag.
  Future<Tag> createTag({required String name, required int color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Tag name cannot be empty');
    }
    final id = _generateId();
    final tag = Tag(id: id, name: trimmed, color: color);
    _tags = [..._tags, tag];
    await _persistTags();
    notifyListeners();
    return tag;
  }

  /// Update an existing tag (matched by id).
  Future<void> updateTag(Tag tag) async {
    final idx = _tags.indexWhere((t) => t.id == tag.id);
    if (idx < 0) return;
    final newList = List<Tag>.from(_tags);
    newList[idx] = tag.copyWith(name: tag.name.trim());
    _tags = newList;
    await _persistTags();
    notifyListeners();
  }

  /// Delete a tag. Also strips the tag id from any file mappings.
  Future<void> deleteTag(String tagId) async {
    if (!_tags.any((t) => t.id == tagId)) return;
    _tags = _tags.where((t) => t.id != tagId).toList();
    _fileTagMap = _fileTagMap.map(
      (k, v) => MapEntry(k, v.where((id) => id != tagId).toList()),
    );
    // Drop empty mappings to keep storage tidy.
    _fileTagMap.removeWhere((_, v) => v.isEmpty);
    if (_activeFilterTagId == tagId) _activeFilterTagId = null;
    await _persistTags();
    await _persistFileMap();
    notifyListeners();
  }

  // --- File ↔ tag mapping ---

  /// Replace the full set of tag IDs for [filePath].
  Future<void> setFileTags(String filePath, List<String> tagIds) async {
    final cleaned = tagIds.toSet().toList(growable: false);
    if (cleaned.isEmpty) {
      _fileTagMap.remove(filePath);
    } else {
      _fileTagMap[filePath] = cleaned;
    }
    await _persistFileMap();
    notifyListeners();
  }

  /// Toggle a single tag on/off for [filePath].
  Future<void> toggleFileTag(String filePath, String tagId) async {
    final current = List<String>.from(_fileTagMap[filePath] ?? const []);
    if (current.contains(tagId)) {
      current.remove(tagId);
    } else {
      current.add(tagId);
    }
    await setFileTags(filePath, current);
  }

  /// Reload tags and file→tag map from persistent storage.
  Future<void> reload() async {
    _tags = _service.getAllTags();
    _fileTagMap = _service.getFileTagMap();
    notifyListeners();
  }

  /// Drop the mapping for [filePath] entirely (e.g. on file deletion).
  Future<void> forgetFile(String filePath) async {
    if (_fileTagMap.remove(filePath) != null) {
      await _persistFileMap();
      notifyListeners();
    }
  }

  // --- Persistence helpers ---

  Future<void> _persistTags() => _service.saveTags(_tags);
  Future<void> _persistFileMap() => _service.saveFileTagMap(_fileTagMap);

  /// Generate a unique-ish id. Timestamp-based — collision-free in practice
  /// for a single-user app, no need to pull in the uuid package.
  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'tag_$now';
  }
}
