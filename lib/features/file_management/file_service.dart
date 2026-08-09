// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';

class FileService {
  /// Scan a directory (non-recursive) for .pdf files, sorted by modified time (newest first).
  /// Only returns files directly in [dirPath], not in subdirectories.
  static Future<List<PdfFile>> scanDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final pdfFiles = <PdfFile>[];
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is File &&
            (entity.path.endsWith('.pdf') ||
             entity.path.endsWith('.pdf.enc') ||
             entity.path.endsWith('.svg'))) {
          try {
            pdfFiles.add(PdfFile.fromFileSystem(entity));
          } catch (e) {
            debugPrint('FileService: error scanning ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('FileService: error listing directory $dirPath: $e');
    }

    pdfFiles.sort((a, b) => b.modified.compareTo(a.modified));
    return pdfFiles;
  }

  /// Scan a directory recursively for .pdf files using an isolate (off main thread).
  /// [maxDepth] limits how deep to scan (default 10). Pass null for unlimited depth.
  /// Falls back to non-recursive scan for simple cases.
  static Future<List<PdfFile>> scanDirectoryRecursive(String dirPath,
      {int? maxDepth = 10}) async {
    final result = await Isolate.run(() {
      final errors = <String>[];
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        errors.add('Directory does not exist or not accessible: $dirPath');
        return _ScanResult([], errors);
      }

      final pdfFiles = <PdfFile>[];
      final stack = [_ScanEntry(dirPath, 0)];

      while (stack.isNotEmpty) {
        final entry = stack.removeLast();
        if (maxDepth != null && entry.depth > maxDepth) continue;

        List<FileSystemEntity> entities;
        try {
          entities = Directory(entry.path).listSync(followLinks: false);
        } catch (e) {
          errors.add('FileService: error listing directory ${entry.path}: $e');
          continue;
        }

        for (final entity in entities) {
          if (entity is File &&
              (entity.path.endsWith('.pdf') ||
                  entity.path.endsWith('.pdf.enc') ||
                  entity.path.endsWith('.svg'))) {
            try {
              pdfFiles.add(PdfFile.fromFileSystem(entity));
            } catch (e) {
              errors.add('FileService: error scanning ${entity.path}: $e');
            }
          } else if (entity is Directory) {
            stack.add(_ScanEntry(entity.path, entry.depth + 1));
          }
        }
      }

      pdfFiles.sort((a, b) => b.modified.compareTo(a.modified));
      return _ScanResult(pdfFiles, errors);
    });
    for (final error in result.errors) {
      debugPrint('FileService: $error');
    }
    return result.files;
  }

  /// Read file bytes (for non-encrypted PDFs).
  static Future<Uint8List> readFileBytes(String path) async {
    final file = File(path);
    return await file.readAsBytes();
  }

  /// Write bytes to file.
  static Future<void> writeFileBytes(String path, Uint8List bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes);
  }

  /// Delete a file.
  static Future<bool> deleteFile(String path) async {
    try {
      final file = File(path);
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rename a file.
  static Future<bool> renameFile(String oldPath, String newPath) async {
    try {
      final file = File(oldPath);
      await file.rename(newPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get the parent directory path.
  static String parentDir(String path) {
    return Directory(path).parent.path;
  }

  /// Get the directory name from a path.
  static String dirName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  /// Check if a directory is readable.
  static Future<bool> isReadable(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return false;
      // Just check we can list — don't require files to exist
      await for (final _ in dir.list(followLinks: false)) {
        return true; // found at least one entry
      }
      return true; // empty dir is still readable
    } catch (e) {
      debugPrint('FileService.isReadable: $path → $e');
      return false;
    }
  }
}

/// Internal helper for stack-based recursive directory traversal.
class _ScanEntry {
  final String path;
  final int depth;
  const _ScanEntry(this.path, this.depth);
}

/// Internal result from isolate-based directory scanning.
class _ScanResult {
  final List<PdfFile> files;
  final List<String> errors;
  const _ScanResult(this.files, this.errors);
}
