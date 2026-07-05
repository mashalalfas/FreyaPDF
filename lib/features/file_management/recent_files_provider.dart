import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';

class RecentFilesProvider extends ChangeNotifier {
  static const int _maxRecentFiles = 5;
  static const String _recentFileName = 'recent_pdf_files.json';

  List<String> _recentFiles = [];

  List<String> get recentFilePaths => List.unmodifiable(_recentFiles);

  /// Returns recent files that exist in [currentFiles], in most-recent order.
  List<PdfFile> getRecentFilesInDir(List<PdfFile> currentFiles) {
    if (_recentFiles.isEmpty) return const [];

    final fileMap = {for (final f in currentFiles) f.path: f};
    final result = _recentFiles
        .map((path) => fileMap[path])
        .whereType<PdfFile>()
        .toList();

    return result;
  }

  Future<void> loadRecentFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_recentFileName');
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents) as List<dynamic>;
        _recentFiles = data.cast<String>();
      }
    } catch (_) {
      // Ignore errors loading recent files
    }
    notifyListeners();
  }

  Future<void> _saveRecentFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_recentFileName');
      await file.writeAsString(jsonEncode(_recentFiles));
    } catch (_) {
      // Ignore errors saving recent files
    }
  }

  void addToRecent(String path) {
    _recentFiles.remove(path);
    _recentFiles.insert(0, path);
    if (_recentFiles.length > _maxRecentFiles) {
      _recentFiles = _recentFiles.sublist(0, _maxRecentFiles);
    }
    _saveRecentFiles();
    notifyListeners();
  }
}
