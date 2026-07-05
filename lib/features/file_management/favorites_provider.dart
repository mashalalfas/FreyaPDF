import 'package:flutter/material.dart';
import 'package:feya_pdf/features/settings/settings_service.dart';

/// Manages favorite file paths, backed by [SettingsService].
class FavoritesProvider extends ChangeNotifier {
  final SettingsService _service;
  Set<String> _favoritePaths = {};

  FavoritesProvider(this._service) {
    _favoritePaths = _service.getFavorites();
  }

  /// Check if a given path is in the favorites list.
  bool isFavorite(String path) => _favoritePaths.contains(path);

  /// Toggle the favorite status of [path].
  /// Persists the change and notifies listeners.
  Future<void> toggleFavorite(String path) async {
    final isFav = _favoritePaths.contains(path);
    await _service.setFavorite(path, !isFav);
    if (isFav) {
      _favoritePaths.remove(path);
    } else {
      _favoritePaths.add(path);
    }
    notifyListeners();
  }

  /// Returns an unmodifiable view of the current favorite paths.
  Set<String> getFavorites() => Set.unmodifiable(_favoritePaths);

  /// Reload favorites from the underlying service.
  Future<void> reload() async {
    _favoritePaths = _service.getFavorites();
    notifyListeners();
  }
}
