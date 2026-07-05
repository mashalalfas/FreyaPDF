import 'package:flutter/material.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';
import 'package:feya_pdf/features/file_management/file_service.dart';
import 'package:feya_pdf/features/file_management/sort_search_provider.dart';
import 'package:feya_pdf/features/file_management/scanned_paths_provider.dart';

class AppState extends ChangeNotifier {
  String? _currentDir;
  List<PdfFile> _files = [];
  bool _isLoading = false;
  String? _error;
  final _fileCache = <String, List<PdfFile>>{};
  PdfFile? _selectedFile;
  SortSearchProvider? _sortSearchProvider;
  ScannedPathsProvider? _scannedPathsProvider;

  void attachSortSearch(SortSearchProvider provider) {
    _sortSearchProvider = provider;
  }

  void attachScannedPaths(ScannedPathsProvider provider) {
    _scannedPathsProvider = provider;
  }

  void invalidateCache() {
    _fileCache.clear();
    notifyListeners();
  }

  String? get currentDir => _currentDir;
  PdfFile? get selectedFile => _selectedFile;
  bool get hasFiles => _files.isNotEmpty;
  String get dirName =>
      _currentDir != null ? _currentDir!.split('/').last : '';
  bool get isLoading => _isLoading;
  String? get error => _error;

    List<PdfFile> get files {
    if (_sortSearchProvider != null) return _sortSearchProvider!.apply(_files);
    return List<PdfFile>.from(_files);
  }

  /// Sorted files with optional favorites-first support.
  List<PdfFile> sortedFiles({Set<String>? favoritePaths}) {
    if (_sortSearchProvider != null) {
      return _sortSearchProvider!.apply(_files, favoritePaths: favoritePaths);
    }
    return List<PdfFile>.from(_files);
  }

  List<PdfFile> get allFiles => _files;

  Future<void> loadDirectory(String path) async {
    _isLoading = true;
    _error = null;
    _selectedFile = null;
    _currentDir = path;
    notifyListeners();
    try {
      final readable = await FileService.isReadable(path);
      if (!readable) {
        _error = 'Cannot read this directory';
        _isLoading = false;
        notifyListeners();
        return;
      }
      _files = _fileCache.containsKey(path)
          ? List.unmodifiable(_fileCache[path]!)
          : await FileService.scanDirectoryRecursive(path, maxDepth: 10);
      if (_files.isNotEmpty) {
        _fileCache[path] = List.unmodifiable(_files);
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load directory: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectFile(PdfFile file) {
    _selectedFile = file;
    notifyListeners();
  }

  void closeFile() {
    _selectedFile = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    _fileCache.clear();
    if (_scannedPathsProvider != null) {
      final paths = await _scannedPathsProvider!.loadScannedPaths();
      if (paths.isNotEmpty) {
        await loadAllDirectories(paths);
        return;
      }
    }
    if (_currentDir != null) await loadDirectory(_currentDir!);
  }

  Future<void> loadAllDirectories(List<String> paths) async {
    if (paths.isEmpty) {
      _files = [];
      _currentDir = null;
      _isLoading = false;
      _error = null;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    _selectedFile = null;
    _currentDir = paths.first;
    notifyListeners();
    final results = await Future.wait(
      paths.map((path) async {
        try {
          if (await FileService.isReadable(path)) {
            final dirFiles = _fileCache.containsKey(path)
                ? _fileCache[path]!
                : await FileService.scanDirectoryRecursive(path, maxDepth: 10);
            if (dirFiles.isNotEmpty) {
              _fileCache[path] = List.unmodifiable(dirFiles);
            }
            return dirFiles;
          }
        } catch (e) {
          debugPrint('AppState: failed to scan directory $path: $e');
          return <PdfFile>[];
        }
        return <PdfFile>[];
      }),
    );
    _files = results.expand((list) => list).toList();
    _isLoading = false;
    notifyListeners();
  }
}
