import 'package:flutter/foundation.dart';

/// Manages multi-select state across the file browser.
///
/// Tracks which file paths are currently selected and toggles
/// selection mode. Consumed by the batch operations toolbar and
/// the file grid/list widgets.
class SelectionProvider extends ChangeNotifier {
  final Set<String> _selectedPaths = {};
  bool _isSelectionMode = false;

  // --- Getters ---

  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);

  bool get isSelectionMode => _isSelectionMode;

  int get selectedCount => _selectedPaths.length;

  // --- Mode control ---

  void enterSelectionMode() {
    if (_isSelectionMode) return;
    _isSelectionMode = true;
    notifyListeners();
  }

  void exitSelectionMode() {
    if (!_isSelectionMode) return;
    _selectedPaths.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  // --- Selection toggles ---

  void toggleSelection(String path) {
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
      // Auto-exit when last item is deselected.
      if (_selectedPaths.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      if (!_isSelectionMode) {
        _isSelectionMode = true;
      }
      _selectedPaths.add(path);
    }
    notifyListeners();
  }

  bool isSelected(String path) => _selectedPaths.contains(path);

  void selectAll(List<String> paths) {
    _selectedPaths.addAll(paths);
    if (_selectedPaths.isNotEmpty) {
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedPaths.clear();
    notifyListeners();
  }
}
