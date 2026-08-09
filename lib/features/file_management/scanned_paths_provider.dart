// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/file_management/file_service.dart';

class ScannedPathsProvider extends ChangeNotifier {
  static const String _scannedPathsKey = 'scanned_paths';
  static const String _lastDirKey = 'last_dir';

  List<String> _scannedPaths = [];
  String? _persistedDir;

  List<String> get scannedPaths => List.unmodifiable(_scannedPaths);
  String? get persistedDir => _persistedDir;

  Future<List<String>> loadScannedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    _scannedPaths = prefs.getStringList(_scannedPathsKey) ?? [];
    return _scannedPaths;
  }

  Future<void> _saveScannedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_scannedPathsKey, _scannedPaths);
  }

  Future<void> addScannedPath(String path) async {
    if (!_scannedPaths.contains(path)) {
      _scannedPaths.add(path);
      _scannedPaths.sort();
      await _saveScannedPaths();
      notifyListeners();
    }
  }

  Future<String?> loadPersistedDir() async {
    final prefs = await SharedPreferences.getInstance();
    _persistedDir = prefs.getString(_lastDirKey);
    return _persistedDir;
  }

  Future<void> savePersistedDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDirKey, path);
    _persistedDir = path;
    notifyListeners();
  }

  Future<void> persistAfterPick(String path) async {
    await savePersistedDir(path);
    await addScannedPath(path);
  }

  /// Scan all paths and return combined PdfFile lists per path.
  /// Uses [cache] to avoid redundant directory scans.
  Future<List<FileScanResult>> scanAllDirectories(
    List<String> paths, {
    Map<String, List<PdfFile>>? cache,
  }) async {
    final results = <FileScanResult>[];
    final cacheMap = cache ?? <String, List<PdfFile>>{};

    for (final path in paths) {
      try {
        final readable = await FileService.isReadable(path);
        if (!readable) continue;

        final dirFiles = cacheMap.containsKey(path)
            ? cacheMap[path]!
            : await FileService.scanDirectoryRecursive(path, maxDepth: 10);
        cacheMap[path] = List.unmodifiable(dirFiles);
        results.add(FileScanResult(path: path, files: dirFiles));
      } catch (_) {
        // skip unreadable paths
      }
    }

    return results;
  }

  /// Get the folder name that contains this file, based on scanned paths.
  String getSourceDirName(String filePath, {String? currentDir}) {
    for (final path in _scannedPaths) {
      if (filePath.startsWith(path)) {
        return path.split('/').last;
      }
    }
    return currentDir?.split('/').last ?? '';
  }
}

/// Result of scanning one directory path.
class FileScanResult {
  final String path;
  final List<PdfFile> files;
  const FileScanResult({required this.path, required this.files});
}
