// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:freya_pdf/core/widgets/freya_snack_bar.dart';
import 'package:freya_pdf/core/widgets/empty_state.dart';
import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/file_management/widgets/file_list_tile.dart';
import 'package:freya_pdf/features/encryption/widgets/passphrase_dialog.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_import_dialog.dart';
import 'package:freya_pdf/features/viewer/viewer_screen.dart';

/// Dedicated full-screen page showing only the secure folder content.
///
/// Completely independent of the home screen: it owns the locked/unlocked
/// state, the encrypted file list (newest first), per-file actions
/// (open via the decrypted read path, export, delete), and the import action.
/// It refreshes the file list each time the page is opened via [loadFiles]
/// so it always reflects the latest secure-folder state.
class SecureFolderScreen extends StatefulWidget {
  const SecureFolderScreen({super.key});

  @override
  State<SecureFolderScreen> createState() => _SecureFolderScreenState();
}

class _SecureFolderScreenState extends State<SecureFolderScreen> {
  /// Tracks the last known file count so the (compact) header can show a count
  /// even while the folder is locked (provider clears its file list on lock).
  int _lastKnownFileCount = 0;

  @override
  void initState() {
    super.initState();
    // Refresh on open so the page reflects the latest secure-folder state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SecureFolderProvider>();
      if (provider.isLocked) {
        _lastKnownFileCount = provider.fileCount;
      } else {
        provider.loadFiles();
      }
    });
  }

  Future<void> _handleUnlock() async {
    final encryption = context.read<EncryptionProvider>();
    if (!encryption.hasPassphrase) {
      final set = await showPassphraseDialog(context);
      if (!set || !mounted) return;
    }
    final provider = context.read<SecureFolderProvider>();
    final success = await provider.unlock();
    if (success && mounted) {
      setState(() => _lastKnownFileCount = provider.fileCount);
    } else if (mounted && provider.error != null) {
      FreyaSnackBar.show(context, provider.error!);
    }
  }

  void _handleLock() {
    final provider = context.read<SecureFolderProvider>();
    _lastKnownFileCount = provider.fileCount;
    provider.lock();
  }

  void _openSecureFile(PdfFile file) {
    final appState = context.read<AppState>();
    appState.selectFile(file);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => ViewerScreen(file: file),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _deleteSecureFile(PdfFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from secure folder?'),
        content: Text(
          'Permanently delete "${file.displayName}" from the secure folder?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<SecureFolderProvider>();
    final success = await provider.deleteFile(file);
    if (mounted && success) {
      setState(() => _lastKnownFileCount = provider.fileCount);
      FreyaSnackBar.show(context, '${file.displayName} deleted');
    }
  }

  Future<void> _exportSecureFile(PdfFile file) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${docsDir.path}/FreyaPDF_Exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      // Derive the plain-text PDF name from the .enc filename
      final plainName = file.displayName;
      final destPath = '${exportDir.path}/$plainName';

      if (!mounted) return;
      final provider = context.read<SecureFolderProvider>();
      final result = await provider.exportFile(file, destPath);
      if (!mounted) return;
      if (result != null) {
        FreyaSnackBar.show(context, 'Exported to FreyaPDF_Exports');
      } else if (provider.error != null) {
        FreyaSnackBar.show(context, provider.error!);
      }
    } catch (e) {
      if (mounted) {
        FreyaSnackBar.show(context, 'Export failed: $e');
      }
    }
  }

  Future<void> _showImportDialog() async {
    final provider = context.read<SecureFolderProvider>();

    // Snapshot the generation before opening; after the dialog closes, if it
    // advanced then an import batch was started (which may still be running in
    // the background if the dialog was dismissed) and we await its summary.
    final gen = provider.importGeneration;
    await showSecureFolderImportDialog(context);
    if (!mounted || provider.importGeneration == gen) return;

    // Await the provider-owned batch so the summary is shown even when the
    // dialog was dismissed to background. `activeImport` is kept by the
    // provider, so if the batch already finished we resolve immediately.
    final result = await provider.activeImport;
    if (!mounted || result == null) return;

    if (result.failed == 0) {
      FreyaSnackBar.show(
        context,
        'Imported ${result.imported} file'
        '${result.imported == 1 ? '' : 's'} to secure folder',
      );
    } else {
      FreyaSnackBar.show(context, '${result.imported} imported, ${result.failed} failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SecureFolderProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Folder'),
      ),
      body: provider.isLocked
          ? _LockedView(
              fileCount: _lastKnownFileCount,
              onUnlock: _handleUnlock,
            )
          : _buildUnlocked(context, provider, colorScheme),
    );
  }

  Widget _buildUnlocked(
    BuildContext context,
    SecureFolderProvider provider,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact header row with lock + import controls.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text(
                '${provider.fileCount} file${provider.fileCount == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: provider.isImporting ? null : _showImportDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Import'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  textStyle: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.lock_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Lock secure folder',
                visualDensity: VisualDensity.compact,
                onPressed: _handleLock,
              ),
            ],
          ),
        ),
        // Live import progress chip — visible even after the dialog is
        // dismissed to background, so the user keeps seeing progress.
        if (provider.isImporting)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: provider.importProgress > 0
                        ? provider.importProgress
                        : null,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Importing ${provider.importCompleted} of '
                    '${provider.importTotal}…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _buildBody(context, provider, colorScheme),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    SecureFolderProvider provider,
    ColorScheme colorScheme,
  ) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            provider.error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
              color: colorScheme.error,
            ),
          ),
        ),
      );
    }
    if (provider.files.isEmpty) {
      return _emptyState(context, colorScheme);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: provider.files.length,
      itemBuilder: (context, index) {
        final file = provider.files[index];
        return FileListTile(
          file: file,
          isSelected: false,
          onTap: () => _openSecureFile(file),
          onDelete: () => _deleteSecureFile(file),
          onShare: () => _exportSecureFile(file),
          onEncrypt: null,
          onTag: null,
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, ColorScheme colorScheme) {
    return EmptyState(
      title: 'No files in secure folder',
      subtitle: 'Encrypted files you add will appear here',
      action: OutlinedButton.icon(
        onPressed: _showImportDialog,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Import files'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Locked-state view shown when the secure folder is locked.
class _LockedView extends StatelessWidget {
  final int fileCount;
  final VoidCallback onUnlock;

  const _LockedView({
    required this.fileCount,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.tertiary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_rounded,
                size: 34,
                color: colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Secure Folder is locked',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              fileCount > 0
                  ? '$fileCount encrypted file${fileCount == 1 ? '' : 's'} protected'
                  : 'Your encrypted files are password protected',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Unlock'),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.tertiary,
                foregroundColor: colorScheme.onTertiary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
