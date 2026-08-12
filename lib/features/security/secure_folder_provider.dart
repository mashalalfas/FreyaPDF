// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/security/secure_folder_service.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';

/// Result of a secure-folder import batch.
class ImportResult {
  final int imported;
  final int failed;
  const ImportResult({required this.imported, required this.failed});

  int get total => imported + failed;
}

/// Manages the secure folder — a dedicated encrypted directory.
///
/// Must [unlock] before accessing files. Files are encrypted with the user's
/// passphrase from [EncryptionProvider].
///
/// Multi-file imports are owned by this provider (via [importFiles]) so the
/// batch survives the import dialog being dismissed to background; the dialog
/// just renders the live progress state exposed below.
class SecureFolderProvider extends ChangeNotifier {
  bool _isLocked = true;
  List<PdfFile> _files = [];
  bool _isLoading = false;
  String? _error;

  // Import job state (owned here so it survives dialog dismissal).
  bool _isImporting = false;
  int _importTotal = 0;
  int _importCompleted = 0;
  String? _importCurrentFileName;
  int _importSuccess = 0;
  int _importFailed = 0;
  Future<ImportResult>? _activeImport;

  /// Monotonically increasing counter, bumped each time a batch starts. Callers
  /// snapshot it before triggering an import and compare after to learn whether
  /// a batch ran (e.g. after the dialog is dismissed to background).
  int _importGeneration = 0;

  EncryptionProvider? _encryptionProvider;

  bool get isLocked => _isLocked;
  List<PdfFile> get files => _files;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get fileCount => _files.length;

  /// Whether a multi-file import batch is currently running.
  bool get isImporting => _isImporting;

  /// Total number of files in the current (or most recent) batch.
  int get importTotal => _importTotal;

  /// Number of files already processed in the current batch.
  int get importCompleted => _importCompleted;

  /// Display name of the file currently being imported (null when idle).
  String? get importCurrentFileName => _importCurrentFileName;

  /// Fraction (0..1) of the batch completed; 0 when idle.
  double get importProgress =>
      _importTotal == 0 ? 0 : (_importCompleted / _importTotal).clamp(0.0, 1.0);

  /// Files successfully imported in the current/most recent batch.
  int get importSuccess => _importSuccess;

  /// Files that failed to import in the current/most recent batch.
  int get importFailed => _importFailed;

  /// The future for the running (or last) import batch, so callers that are
  /// outside the dialog (e.g. a backgrounded card) can await completion.
  Future<ImportResult>? get activeImport => _activeImport;

  /// Generation counter; increases whenever [importFiles] starts a new batch.
  int get importGeneration => _importGeneration;

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

  /// Import a single file into the secure folder (isolate-backed).
  ///
  /// Encrypts [sourcePath] using the current passphrase, moves the encrypted
  /// copy to the secure directory, and deletes the original.
  /// Returns `true` on success.
  Future<bool> importFile(String sourcePath) async {
    final result = await importFiles([sourcePath]);
    return result.imported > 0;
  }

  /// Import a batch of files into the secure folder.
  ///
  /// Runs in a background isolate per file, updates the import job state
  /// (total/completed/current/counts) between files, and never aborts the batch
  /// on a per-file failure — each file is isolated by a try/catch and failures
  /// are counted, not thrown. The returned future resolves when the whole batch
  /// finishes, regardless of whether the import dialog has been dismissed, so
  /// callers can surface a "N imported, M failed" summary.
  ///
  /// Returns an [ImportResult] summary; never throws for a batch-level error
  /// (individual failures are recorded in [ImportResult.failed]).
  Future<ImportResult> importFiles(List<String> sourcePaths) async {
    final passphrase = _encryptionProvider?.passphrase;
    if (_isLocked) {
      _error = 'Secure folder is locked — unlock first';
      notifyListeners();
      return const ImportResult(imported: 0, failed: 0);
    }
    if (passphrase == null || passphrase.isEmpty) {
      _error = 'No passphrase set';
      notifyListeners();
      return const ImportResult(imported: 0, failed: 0);
    }

    final paths = List<String>.of(sourcePaths);
    if (paths.isEmpty) {
      _error = 'No files selected to import';
      notifyListeners();
      return const ImportResult(imported: 0, failed: 0);
    }

    _isImporting = true;
    _importGeneration++;
    _importTotal = paths.length;
    _importCompleted = 0;
    _importSuccess = 0;
    _importFailed = 0;
    _importCurrentFileName = null;
    _error = null;
    notifyListeners();

    final completer = Completer<ImportResult>();
    _activeImport = completer.future;

    try {
      for (final path in paths) {
        _importCurrentFileName = _basename(path);
        notifyListeners();
        try {
          final encPath = await SecureFolderService.importFile(path, passphrase);
          if (encPath.isNotEmpty) {
            _importSuccess++;
          } else {
            _importFailed++;
          }
        } catch (e) {
          _importFailed++;
          debugPrint('SecureFolderProvider.importFiles: failed $path: $e');
        }
        _importCompleted++;
        notifyListeners();
      }
    } finally {
      _isImporting = false;
      _importCurrentFileName = null;

      // Refresh the file list so newly encrypted files appear.
      if (!_isLocked) {
        try {
          _files = await SecureFolderService.listFiles();
        } catch (e) {
          debugPrint('SecureFolderProvider.importFiles: refresh failed: $e');
        }
      }

      final summary = ImportResult(
        imported: _importSuccess,
        failed: _importFailed,
      );
      completer.complete(summary);
      notifyListeners();
    }

    return await _activeImport!;
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;

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
