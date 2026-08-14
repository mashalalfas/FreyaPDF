// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:freya_pdf/features/settings/backup_service.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:freya_pdf/features/file_management/favorites_provider.dart';
import 'package:freya_pdf/features/highlights/highlight_provider.dart';
import 'package:freya_pdf/features/file_management/recent_files_provider.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/tags/tag_provider.dart';

/// Manages backup export/import UI and orchestration.
class BackupProvider extends ChangeNotifier {
  final BackupService _backupService;

  bool _isExporting = false;
  bool _isImporting = false;
  String? _lastExportPath;

  BackupProvider(this._backupService);

  // ---- Getters ----

  bool get isExporting => _isExporting;
  bool get isImporting => _isImporting;
  String? get lastExportPath => _lastExportPath;

  // ---- Export ----

  /// Collect all app state, encrypt it with a user-supplied passphrase,
  /// write the result to a `.freya` file, and share it.
  Future<void> exportBackup(BuildContext context) async {
    if (_isExporting) return;
    _isExporting = true;
    notifyListeners();

    try {
      // 1. Ask user for the encryption passphrase (and confirm it).
      if (!context.mounted) return;
      final passphrase = await _promptPassphrase(
        context,
        title: 'Encrypt backup',
        message:
            'Choose a passphrase to encrypt this backup. You\'ll need the '
            'same passphrase to restore it later. If you forget it, the '
            'backup cannot be recovered.',
        confirm: true,
      );
      if (passphrase == null) {
        _isExporting = false;
        notifyListeners();
        return;
      }

      // 2. Gather data from providers and build the JSON.
      if (!context.mounted) {
        _isExporting = false;
        notifyListeners();
        return;
      }
      final recentFilesProvider = context.read<RecentFilesProvider>();
      final json = await _backupService.exportAll(
        recentFilePaths: recentFilesProvider.recentFilePaths.toList(),
      );

      // 3. Encrypt + write to a temp file with `.freya` extension.
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${dir.path}/FreyaPDF_backup_$timestamp.freya';
      final payload = _backupService.encryptBackupJson(json, passphrase);
      final file = File(filePath);
      await file.writeAsBytes(payload);

      _lastExportPath = filePath;

      // 4. Share the encrypted backup file.
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'FreyaPDF Backup (encrypted)',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Encrypted backup saved: FreyaPDF_backup_$timestamp.freya'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  // ---- Import ----

  /// Pick a backup file (`.json` plain or `.freya` encrypted), confirm
  /// with the user, then restore.
  Future<void> importBackup(BuildContext context) async {
    if (_isImporting) return;

    // Step 1: Pick a file — accept both the legacy `.json` extension and
    // the new encrypted `.freya` extension.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['freya', 'json'],
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    // Step 2: Read the file as raw bytes so we can detect the encrypted
    // magic header before deciding whether a passphrase is required.
    Uint8List bytes;
    try {
      bytes = await File(filePath).readAsBytes();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read backup file: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    final isEncrypted = BackupService.looksEncrypted(bytes);

    // Step 3: If encrypted, prompt for the passphrase and decrypt.
    String json;
    if (isEncrypted) {
      // Allow up to 3 attempts to enter the correct passphrase.
      String? decrypted;
      for (var attempt = 0; attempt < 3 && decrypted == null; attempt++) {
        if (!context.mounted) return;
        final passphrase = await _promptPassphrase(
          context,
          title: 'Decrypt backup',
          message: attempt == 0
              ? 'This backup is encrypted. Enter the passphrase that was '
                  'used when it was exported.'
              : 'Wrong passphrase. Please try again '
                  '(${2 - attempt} attempt(s) left).',
          confirm: false,
        );
        if (passphrase == null) return;
        try {
          decrypted = _backupService.decryptBackupToJson(bytes, passphrase);
        } on EncryptionException {
          // try again
        }
      }
      if (decrypted == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not decrypt backup — wrong passphrase?'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }
      json = decrypted;
    } else {
      // Legacy / plain JSON backup.
      json = utf8.decode(bytes);
    }

    // Step 4: Parse and build summary for confirmation dialog
    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      // Let the service handle parsing errors
    }

    // Quick summary
    int tagCount = 0;
    int highlightCount = 0;
    int bookmarkCount = 0;
    int favoriteCount = 0;
    int recentFileCount = 0;

    if (parsed != null) {
      final data = parsed['data'] as Map<String, dynamic>?;
      if (data != null) {
        tagCount = _listLength(data['tags']);
        highlightCount = _listLength(data['highlights']);
        bookmarkCount = _listLength(data['bookmarks']);
        favoriteCount = _listLength(data['favorites']);
        recentFileCount = _listLength(data['recentFiles']);
      }
    }

    // Step 4: Confirmation dialog
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Restore Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will replace your current data with the backup.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            _summaryRow(ctx, 'Tags', tagCount),
            _summaryRow(ctx, 'Highlights', highlightCount),
            _summaryRow(ctx, 'Bookmarks', bookmarkCount),
            _summaryRow(ctx, 'Favorites', favoriteCount),
            _summaryRow(ctx, 'Recent files', recentFileCount),
            const SizedBox(height: 8),
            Text(
              'Settings and last-read positions will also be restored.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Step 5: Perform the import
    _isImporting = true;
    notifyListeners();

    try {
      final success = await _backupService.importFromJson(json);

      if (success) {
        // Reload all providers with fresh data
        if (context.mounted) {
          context.read<HighlightProvider>().reload();
          context.read<BookmarkProvider>().reload();
          context.read<SettingsProvider>().reload();
          context.read<FavoritesProvider>().reload();
          context.read<TagProvider>().reload();
          await context.read<RecentFilesProvider>().loadRecentFiles();
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Backup restored successfully'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Failed to restore backup: incompatible schema version',
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  // ---- Helpers ----

  int _listLength(dynamic value) {
    if (value is List) return value.length;
    if (value is Map) return value.length;
    return 0;
  }

  /// Show a passphrase entry dialog.
  ///
  /// - [confirm] `true` requires typing the passphrase twice (used when
  ///   *creating* a new backup passphrase so the user doesn't typo).
  /// - Returns the entered passphrase, or `null` if the user cancelled.
  Future<String?> _promptPassphrase(
    BuildContext context, {
    required String title,
    required String message,
    required bool confirm,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final cs = Theme.of(ctx).colorScheme;
            final firstText = first.text;
            final canSubmit = firstText.isNotEmpty &&
                (!confirm || firstText == second.text);

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.lock_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(title),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: first,
                      autofocus: true,
                      obscureText: obscure1,
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                      decoration: InputDecoration(
                        labelText: 'Passphrase',
                        prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure1
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => obscure1 = !obscure1),
                        ),
                      ),
                    ),
                    if (confirm) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: second,
                        obscureText: obscure2,
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (v != first.text) return 'Passphrases do not match';
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Confirm passphrase',
                          prefixIcon:
                              const Icon(Icons.vpn_key_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscure2
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => obscure2 = !obscure2),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () {
                          if (formKey.currentState!.validate()) {
                            // Copy any pending text and dispose safely
                            // after pop so controllers don't leak.
                            final value = first.text;
                            Navigator.pop(ctx, value);
                          }
                        }
                      : null,
                  child: Text(confirm ? 'Encrypt & Export' : 'Unlock'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      // If the user cancels (returns null), controllers are still alive;
      // they're disposed here either way.
      first.dispose();
      second.dispose();
    });
  }

  Widget _summaryRow(BuildContext context, String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('$label: '),
          Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
