import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/file_management/file_service.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/security/pdf_password_storage.dart';

enum SaveResult { success, alreadyExists, failure }

class FileOperationsProvider extends ChangeNotifier {
  EncryptionProvider? _encryptionProvider;
  final List<File> _tempDecryptedFiles = [];

  void attachEncryption(EncryptionProvider provider) {
    _encryptionProvider = provider;
  }

  Future<bool> deleteFile(PdfFile file) async {
    final success = await FileService.deleteFile(file.path);
    if (success) {
      try {
        await PdfPasswordStorage().delete(file.path);
      } catch (e) {
        // Password cleanup is best-effort and must not undo a file deletion.
        debugPrint('FileOperations: failed to clear PDF password: $e');
      }
      notifyListeners();
    }
    return success;
  }

  /// Encrypt a PDF file (creating a .pdf.enc alongside it).
  /// Returns the new .pdf.enc path, or null on failure.
  Future<String?> encryptFile(PdfFile file) async {
    if (_encryptionProvider == null) return null;
    try {
      final encPath = await _encryptionProvider!.encryptFile(file.path);
      notifyListeners();
      return encPath;
    } on EncryptionException catch (_) {
      return null;
    }
  }

  /// Auto-encrypt a PDF — write encrypted version, delete original.
  Future<bool> autoEncryptFile(PdfFile file) async {
    if (_encryptionProvider == null) return false;
    try {
      await _encryptionProvider!.encryptFile(file.path);
      await File(file.path).delete();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Decrypt a .pdf.enc file to bytes for the viewer.
  Future<Uint8List?> decryptForViewing(PdfFile file) async {
    if (_encryptionProvider == null) return null;
    try {
      return await _encryptionProvider!.decryptFile(file.path);
    } on EncryptionException catch (_) {
      return null;
    }
  }

  /// Read PDF bytes (non-encrypted) for the viewer.
  Future<Uint8List?> readPdfBytes(PdfFile file) async {
    try {
      return await FileService.readFileBytes(file.path);
    } catch (e) {
      return null;
    }
  }

  /// Get decrypted PDF bytes (handles both encrypted and unencrypted).
  Future<Uint8List?> getPdfBytes(PdfFile file) async {
    if (file.isEncrypted) {
      return await decryptForViewing(file);
    }
    return await readPdfBytes(file);
  }

  Future<void> shareFile(String path) async {
    try {
      final file = File(path);
      // For encrypted files, share the decrypted PDF
      if (path.endsWith('.pdf.enc') && _encryptionProvider != null) {
        final bytes = await _encryptionProvider!.decryptFile(path);
        final dir = await getTemporaryDirectory();
        final fileName = path.split('/').last;
        final pdfName = fileName.endsWith('.pdf.enc')
            ? fileName.substring(0, fileName.length - 4)
            : fileName;
        final tempFile = File('${dir.path}/$pdfName');
        await tempFile.writeAsBytes(bytes);
        final xFile = XFile(tempFile.path, mimeType: 'application/pdf');
        await Share.shareXFiles([xFile], text: pdfName);
        await tempFile.delete();
      } else {
        // Share the file directly
        final xFile = XFile(path, mimeType: 'application/pdf');
        await Share.shareXFiles([xFile], text: file.uri.pathSegments.last);
      }
    } catch (e) {
      // Caller handles error display
    }
  }

  // ---------------------------------------------------------------------------
  // Batch operations
  // ---------------------------------------------------------------------------

  /// Delete multiple files. Returns count of successful deletions.
  Future<int> batchDelete(List<String> paths) async {
    var count = 0;
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          count++;
        }
      } catch (_) {
        // Skip files that can't be deleted
      }
    }
    if (count > 0) notifyListeners();
    return count;
  }

  /// Encrypt multiple files. Returns list of paths that were successfully encrypted.
  Future<List<String>> batchEncrypt(List<String> paths) async {
    if (_encryptionProvider == null) return [];
    final encrypted = <String>[];
    for (final path in paths) {
      try {
        final encPath = await _encryptionProvider!.encryptFile(path);
        encrypted.add(encPath);
      } catch (_) {
        // Skip files that can't be encrypted
      }
    }
    if (encrypted.isNotEmpty) notifyListeners();
    return encrypted;
  }

  /// Share multiple files via share_plus.
  Future<void> batchShare(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      final xFiles = <XFile>[];
      for (final path in paths) {
        final file = File(path);
        if (await file.exists()) {
          // For encrypted files, share the decrypted PDF
          if (path.endsWith('.pdf.enc') && _encryptionProvider != null) {
            final bytes = await _encryptionProvider!.decryptFile(path);
            final dir = await getTemporaryDirectory();
            final fileName = path.split('/').last;
            final pdfName = fileName.endsWith('.pdf.enc')
                ? fileName.substring(0, fileName.length - 4)
                : fileName;
            final tempFile = File('${dir.path}/$pdfName');
            await tempFile.writeAsBytes(bytes);
            xFiles.add(XFile(tempFile.path, mimeType: 'application/pdf'));
            _tempDecryptedFiles.add(tempFile);
          } else {
            xFiles.add(XFile(path, mimeType: 'application/pdf'));
          }
        }
      }
      if (xFiles.isNotEmpty) {
        final text = paths.length == 1
            ? paths.first.split('/').last
            : '${paths.length} PDFs';
        await Share.shareXFiles(xFiles, text: text);
        // Clean up any temporary decrypted files created for sharing.
        for (final f in _tempDecryptedFiles) {
          try {
            await f.delete();
          } catch (_) {}
        }
        _tempDecryptedFiles.clear();
      }
    } catch (_) {
      // Caller handles error display
    }
  }

  /// Save a file to a target directory, or the app's local documents FreyaPDF
  /// folder if [targetDir] is null.
  /// Returns a [SaveResult] indicating success, alreadyExists, or failure.
  Future<(SaveResult, String?)> saveToLocal(
    String sourcePath, {
    String? targetDir,
  }) async {
    try {
      final String destDirPath;
      if (targetDir != null) {
        destDirPath = targetDir;
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        destDirPath = '${docsDir.path}/FreyaPDF';
      }

      final localDir = Directory(destDirPath);
      if (!await localDir.exists()) {
        await localDir.create(recursive: true);
      }

      final fileName = sourcePath.split('/').last;
      final destPath = '${localDir.path}/$fileName';

      // Check if file already exists locally
      if (await File(destPath).exists()) {
        return (SaveResult.alreadyExists, destPath);
      }

      // Copy file
      final sourceFile = File(sourcePath);
      await sourceFile.copy(destPath);

      notifyListeners();

      return (SaveResult.success, destPath);
    } catch (e) {
      return (SaveResult.failure, null);
    }
  }
}
