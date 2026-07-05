import 'package:flutter/material.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';

enum SortBy { name, modified, size }
enum SortOrder { asc, desc }

class SortSearchProvider extends ChangeNotifier {
  SortBy _sortBy = SortBy.modified;
  SortOrder _sortOrder = SortOrder.desc;
  String _searchQuery = '';
  bool _favoritesFirst = false;

  SortBy get sortBy => _sortBy;
  SortOrder get sortOrder => _sortOrder;
  String get searchQuery => _searchQuery;
  bool get showFavoritesFirst => _favoritesFirst;

  set sortBy(SortBy value) {
    _sortBy = value;
    notifyListeners();
  }

  set sortOrder(SortOrder value) {
    _sortOrder = value;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleFavoritesFirst() {
    _favoritesFirst = !_favoritesFirst;
    notifyListeners();
  }

  List<PdfFile> apply(List<PdfFile> files, {Set<String>? favoritePaths}) {
    var sorted = List<PdfFile>.from(files);

    // Apply sorting with favorites-first option
    sorted.sort((a, b) {
      // Favorites first
      if (_favoritesFirst && favoritePaths != null) {
        final aFav = favoritePaths.contains(a.path);
        final bFav = favoritePaths.contains(b.path);
        if (aFav != bFav) return aFav ? -1 : 1;
      }
      // Primary sort
      int cmp;
      switch (_sortBy) {
        case SortBy.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortBy.modified:
          cmp = a.modified.compareTo(b.modified);
        case SortBy.size:
          cmp = a.sizeBytes.compareTo(b.sizeBytes);
      }
      return _sortOrder == SortOrder.asc ? cmp : -cmp;
    });

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      sorted = sorted.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    return sorted;
  }
}
