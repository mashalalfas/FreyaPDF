import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';
import 'package:feya_pdf/features/encryption/encryption_service.dart';

/// Manages encrypted files in a dedicated secure folder.
///
/// All files are AES-256-GCM encrypted with the user's passphrase.
/// The secure folder lives at {appDocuments}/FeyaPDF_Secure/.
class SecureFolderService {
  /// Get the secure directory, creating it if it doesn't exist.
  static Future<Directory> getSecureDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final secureDir = Directory('${appDir.path}/FeyaPDF_Secure/');
    if (!await secureDir.exists()) {
      await secureDir.create(recursive: true);
    }
    return secureDir;
  }

  /// Import a file into the secure folder.
  ///
  /// Reads [sourcePath], encrypts with [passphrase], writes the encrypted
  /// copy to the secure folder, then deletes the original.
  /// Returns the path of the new encrypted file.
  ///
  /// Uses atomic write (temp file → rename) for crash safety.
  static Future<String> importFile(
      String sourcePath, String passphrase) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw ArgumentError('Source file not found: $sourcePath');
    }

    final plaintext = await sourceFile.readAsBytes();
    final encrypted =
        EncryptionService.encryptBytes(plaintext, passphrase);

    // Determine filename in secure dir
    final basename = sourcePath.split(Platform.pathSeparator).last;
    final encName = basename.endsWith('.enc') ? basename : '$basename.enc';
    final secureDir = await getSecureDir();
    final encPath = '${secureDir.path}/$encName';
    final tmpPath = '$encPath.tmp';

    try {
      // Atomic write: temp file → rename
      await File(tmpPath).writeAsBytes(encrypted);
      await File(tmpPath).rename(encPath);

      // Delete the original
      await sourceFile.delete();
    } catch (e) {
      // Clean up temp file if something went wrong
      final tmpFile = File(tmpPath);
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      debugPrint('SecureFolderService.importFile: $e');
      rethrow;
    }

    return encPath;
  }

  /// List all encrypted files in the secure folder.
  ///
  /// Returns [PdfFile] instances sorted by modified time (newest first).
  static Future<List<PdfFile>> listFiles() async {
    final secureDir = await getSecureDir();
    if (!await secureDir.exists()) return [];

    final files = <PdfFile>[];
    try {
      await for (final entity
          in secureDir.list(recursive: false, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.pdf.enc')) {
          try {
            files.add(PdfFile.fromFileSystem(entity));
          } catch (e) {
            debugPrint(
                'SecureFolderService: error scanning ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('SecureFolderService: error listing secure folder: $e');
    }

    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// Delete a file from the secure folder.
  ///
  /// Returns `true` if the file was deleted, `false` otherwise.
  static Future<bool> deleteFile(String encPath) async {
    try {
      final file = File(encPath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('SecureFolderService.deleteFile: $e');
      return false;
    }
  }

  /// Check whether [path] resides inside the secure folder.
  static Future<bool> isInSecureFolder(String path) async {
    final secureDir = await getSecureDir();
    return path.startsWith(secureDir.path);
  }

  /// Export (decrypt) a file from the secure folder to [destPath].
  ///
  /// Reads the encrypted file at [encPath], decrypts it with [passphrase],
  /// and writes the plaintext PDF to [destPath].
  /// Uses atomic write (temp file → rename) for crash safety.
  ///
  /// Throws [EncryptionException] if the passphrase is wrong.
  static Future<void> exportFile(
      String encPath, String destPath, String passphrase) async {
    final encFile = File(encPath);
    if (!await encFile.exists()) {
      throw ArgumentError('Encrypted file not found: $encPath');
    }

    final encrypted = await encFile.readAsBytes();
    final plaintext =
        EncryptionService.decryptBytes(encrypted, passphrase);

    final tmpPath = '$destPath.tmp';
    try {
      // Atomic write: temp file → rename
      await File(tmpPath).writeAsBytes(plaintext);
      await File(tmpPath).rename(destPath);
    } catch (e) {
      // Clean up temp file on failure
      final tmpFile = File(tmpPath);
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      debugPrint('SecureFolderService.exportFile: $e');
      rethrow;
    }
  }
}
