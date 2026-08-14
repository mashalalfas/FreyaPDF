// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';

/// Manages encrypted files in a dedicated secure folder.
///
/// All files are AES-256-GCM encrypted with the user's passphrase.
/// The secure folder lives at {appDocuments}/FreyaPDF_Secure/.
class SecureFolderService {
  /// Get the secure directory, creating it if it doesn't exist.
  static Future<Directory> getSecureDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final secureDir = Directory('${appDir.path}/FreyaPDF_Secure/');
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
  ///
  /// The heavy read + PBKDF2(600k) + AES-GCM + write work runs off the main
  /// isolate (this was the ANR root cause: importing 4+ files froze the UI and
  /// the OS killed the app). The secure dir + target paths are computed here on
  /// the main isolate (path_provider needs platform channels), then the whole
  /// read→encrypt→write→delete pipeline runs in a background isolate via
  /// [importFileInIsolate]. The ciphertext format is unchanged (FREYA magic, v2).
  static Future<String> importFile(
      String sourcePath, String passphrase) async {
    if (!await File(sourcePath).exists()) {
      throw ArgumentError('Source file not found: $sourcePath');
    }

    // Compute secure dir + target paths on the main isolate (path_provider
    // requires platform channels and is not available inside Isolate.run).
    final secureDir = await getSecureDir();
    final basename = sourcePath.split(Platform.pathSeparator).last;
    final safeName = _guardImportName(basename);
    final encName =
        safeName.endsWith('.enc') ? safeName : '$safeName.enc';
    final encPath = '${secureDir.path}/$encName';

    // Run read → encrypt → atomic write(temp→rename) → delete-original off the
    // main isolate. Only plain sendable strings cross the boundary.
    return Isolate.run(() => importFileInIsolate(sourcePath, encPath, passphrase));
  }

  /// Reject import filenames that could escape the secure directory.
  ///
  /// Defense-in-depth against path traversal: even though [basename]
  /// extraction strips the path, a crafted name such as `..\x.pdf` or
  /// `a/b.pdf` would otherwise be written outside the secure folder.
  /// Throws [ArgumentError] on an unsafe name.
  static String _guardImportName(String basename) {
    if (basename.isEmpty ||
        basename.contains('..') ||
        basename.contains('/') ||
        basename.contains(r'\')) {
      throw ArgumentError('Unsafe file name for import: $basename');
    }
    return basename;
  }

  /// Isolate entrypoint for [importFile]. Static + argument-only (no closures
  /// capturing non-sendables) so it can run inside `Isolate.run`. Reuses
  /// [EncryptionService.encryptBytes] verbatim — the exact FREYA/v2 format is
  /// preserved, matching existing .enc files on disk.
  ///
  /// Returns the encrypted path on success. Throws on failure; any stale
  /// `.tmp` is best-effort removed and the original source file is preserved.
  static String importFileInIsolate(
      String sourcePath, String encPath, String passphrase) {
    final tmpPath = '$encPath.tmp';
    final sourceFile = File(sourcePath);

    try {
      if (!sourceFile.existsSync()) {
        throw ArgumentError('Source file not found: $sourcePath');
      }

      final plaintext = sourceFile.readAsBytesSync();
      final encrypted = EncryptionService.encryptBytes(plaintext, passphrase);

      // Clear any stale tmp from a previous interrupted run.
      final tmpFile = File(tmpPath);
      if (tmpFile.existsSync()) {
        tmpFile.deleteSync();
      }

      // Atomic write: temp file → rename.
      tmpFile.writeAsBytesSync(encrypted, mode: FileMode.write);
      tmpFile.renameSync(encPath);

      // Only delete the original after the encrypted copy is committed.
      sourceFile.deleteSync();
      return encPath;
    } catch (e) {
      // Best-effort cleanup of the temp file; never mask the original error.
      try {
        final tmpFile = File(tmpPath);
        if (tmpFile.existsSync()) {
          tmpFile.deleteSync();
        }
      } catch (_) {}
      rethrow;
    }
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
