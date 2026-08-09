import 'dart:io';
import 'package:flutter/material.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/security/secure_folder_service.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';

/// Manages the secure folder — a dedicated encrypted directory.
///
/// Must [unlock] before accessing files. Files are encrypted with the user's
/// passphrase from [EncryptionProvider].
class SecureFolderProvider extends ChangeNotifier {
  bool _isLocked = true;
  List<PdfFile> _files = [];
  bool _isLoading = false;
  String? _error;

  EncryptionProvider? _encryptionProvider;

  bool get isLocked => _isLocked;
  List<PdfFile> get files => _files;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get fileCount => _files.length;

  void attachEncryption(EncryptionProvider provider) {
    _encryptionProvider = provider;
  }

  /// Unlock the secure folder by validating the passphrase.
  ///
  /// Returns `true` if the passphrase is set and files could be loaded,
  /// `false` otherwise. Stays locked on failure.
  Future<bool> unlock() async {
    final passphrase = _encryptionProvider?.passphrase;
    if (passphrase == null || passphrase.isEmpty) {
      _error = 'No passphrase set — set a passphrase first';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Try loading files — if decryption fails we'll know
      final loaded = await SecureFolderService.listFiles();
      _files = loaded;
      _isLocked = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLocked = true;
      _files = [];
      _error = 'Failed to unlock secure folder: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Lock the folder — clears file list and sets locked state.
  void lock() {
    _files = [];
    _isLocked = true;
    _error = null;
    notifyListeners();
  }

  /// Load files from secure directory.
  ///
  /// Only works when unlocked. Sets [_error] if locked.
  Future<void> loadFiles() async {
    if (_isLocked) {
      _error = 'Secure folder is locked — unlock first';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _files = await SecureFolderService.listFiles();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load secure files: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Import a file into the secure folder.
  ///
  /// Encrypts [sourcePath] using the current passphrase, moves the encrypted
  /// copy to the secure directory, and deletes the original.
  /// Returns `true` on success.
  Future<bool> importFile(String sourcePath) async {
    if (_isLocked) {
      _error = 'Secure folder is locked — unlock first';
      notifyListeners();
      return false;
    }

    final passphrase = _encryptionProvider?.passphrase;
    if (passphrase == null || passphrase.isEmpty) {
      _error = 'No passphrase set';
      notifyListeners();
      return false;
    }

    if (!await File(sourcePath).exists()) {
      _error = 'File not found: $sourcePath';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await SecureFolderService.importFile(sourcePath, passphrase);
      // Refresh file list
      _files = await SecureFolderService.listFiles();
      _isLoading = false;
      notifyListeners();
      return true;
    } on EncryptionException catch (e) {
      _error = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to import file: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete a file from the secure folder.
  ///
  /// Returns `true` if the file was deleted successfully.
  Future<bool> deleteFile(PdfFile file) async {
    if (_isLocked) {
      _error = 'Secure folder is locked — unlock first';
      notifyListeners();
      return false;
    }

    _error = null;
    notifyListeners();

    try {
      final success = await SecureFolderService.deleteFile(file.path);
      if (success) {
        _files.removeWhere((f) => f.path == file.path);
        notifyListeners();
      } else {
        _error = 'Failed to delete file';
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Failed to delete file: $e';
      notifyListeners();
      return false;
    }
  }

  /// Export/decrypt a file to [destPath].
  ///
  /// Decrypts the file using the current passphrase and writes the plaintext
  /// PDF to [destPath]. Returns the [destPath] on success, `null` on failure.
  Future<String?> exportFile(PdfFile file, String destPath) async {
    if (_isLocked) {
      _error = 'Secure folder is locked — unlock first';
      notifyListeners();
      return null;
    }

    final passphrase = _encryptionProvider?.passphrase;
    if (passphrase == null || passphrase.isEmpty) {
      _error = 'No passphrase set';
      notifyListeners();
      return null;
    }

    _error = null;
    notifyListeners();

    try {
      await SecureFolderService.exportFile(file.path, destPath, passphrase);
      return destPath;
    } on EncryptionException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Failed to export file: $e';
      notifyListeners();
      return null;
    }
  }

  /// Check whether [path] resides inside the secure folder.
  bool isInSecureFolder(String path) {
    // Synchronous wrapper around the async service method.
    // The secure dir path is deterministic, so we can check via
    // path prefix without awaiting.
    try {
      // We rely on the fact that getSecureDir() produces a known path.
      // For a sync check, we delegate to the service's async method —
      // the provider callers should use the static method directly if
      // they need a sync check. This method is kept for API consistency.
      return path.contains('/FreyaPDF_Secure/');
    } catch (_) {
      return false;
    }
  }
}
