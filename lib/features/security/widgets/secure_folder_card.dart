// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/file_management/widgets/file_list_tile.dart';
import 'package:freya_pdf/features/encryption/widgets/passphrase_dialog.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_import_dialog.dart';
import 'package:freya_pdf/features/viewer/viewer_screen.dart';

/// A card widget displaying the secure folder on the home screen.
///
/// Shows a locked/unlocked state with subtle animation between them.
/// Integrates with [SecureFolderProvider] for state management and
/// [EncryptionProvider] for passphrase handling.
class SecureFolderCard extends StatefulWidget {
  const SecureFolderCard({super.key});

  @override
  State<SecureFolderCard> createState() => _SecureFolderCardState();
}

class _SecureFolderCardState extends State<SecureFolderCard> {
  /// Tracks the last known file count for display in locked state.
  int _lastKnownFileCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<SecureFolderProvider>();
        if (!provider.isLocked) {
          _lastKnownFileCount = provider.fileCount;
        }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error!),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
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
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<SecureFolderProvider>();
    final success = await provider.deleteFile(file);
    if (mounted && success) {
      _lastKnownFileCount = provider.fileCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.displayName} deleted'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to FreyaPDF_Exports'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else if (provider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.error!),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showImportDialog() async {
    final imported = await showSecureFolderImportDialog(context);
    if (imported && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Files imported to secure folder'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      // Refresh the file list
      if (mounted) {
        context.read<SecureFolderProvider>().loadFiles();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SecureFolderProvider>();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1.0,
            child: child,
          ),
        );
      },
      child: provider.isLocked
          ? _LockedCard(
              key: const ValueKey('locked'),
              fileCount: _lastKnownFileCount,
              onTap: _handleUnlock,
            )
          : _UnlockedCard(
              key: const ValueKey('unlocked'),
              provider: provider,
              onLock: _handleLock,
              onOpenFile: _openSecureFile,
              onDeleteFile: _deleteSecureFile,
              onExportFile: _exportSecureFile,
              onImport: _showImportDialog,
            ),
    );
  }
}

/// Locked-state card shown when the secure folder is locked.
class _LockedCard extends StatelessWidget {
  final int fileCount;
  final VoidCallback onTap;

  const _LockedCard({
    super.key,
    required this.fileCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 22,
                    color: colorScheme.tertiary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure Folder',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to unlock',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (fileCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$fileCount',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Unlocked-state card shown when the secure folder is unlocked.
class _UnlockedCard extends StatelessWidget {
  final SecureFolderProvider provider;
  final VoidCallback onLock;
  final void Function(PdfFile) onOpenFile;
  final void Function(PdfFile) onDeleteFile;
  final void Function(PdfFile) onExportFile;
  final VoidCallback onImport;

  const _UnlockedCard({
    super.key,
    required this.provider,
    required this.onLock,
    required this.onOpenFile,
    required this.onDeleteFile,
    required this.onExportFile,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colorScheme.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.lock_open_rounded,
                      size: 18,
                      color: colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Secure Folder',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${provider.fileCount} file${provider.fileCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.lock_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Lock secure folder',
                    visualDensity: VisualDensity.compact,
                    onPressed: onLock,
                  ),
                ],
              ),
            ),
            if (provider.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  provider.error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.error,
                  ),
                ),
              )
            else if (provider.files.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 36,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No files in secure folder',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              // File list using FileListTile
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: provider.files.length,
                itemBuilder: (context, index) {
                  final file = provider.files[index];
                  return FileListTile(
                    file: file,
                    isSelected: false,
                    onTap: () => onOpenFile(file),
                    onDelete: () => onDeleteFile(file),
                    onShare: () => onExportFile(file),
                    onEncrypt: null,
                    onTag: null,
                  );
                },
              ),
            // Import button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Import files'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    side: BorderSide(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
