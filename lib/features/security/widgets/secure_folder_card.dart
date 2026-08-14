// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_screen.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_import_dialog.dart';

/// A compact entry card for the secure folder on the home screen.
///
/// This replaced the old inline file list to reclaim home-screen real estate
/// when many files are added. It shows a compact summary row (icon + title +
/// file count), keeps the live background-import progress chip, and surfaces
/// the import-completion summary. Tapping the card opens the dedicated
/// [SecureFolderScreen] which renders the full secure-folder content.
class SecureFolderCard extends StatefulWidget {
  const SecureFolderCard({super.key});

  @override
  State<SecureFolderCard> createState() => _SecureFolderCardState();
}

class _SecureFolderCardState extends State<SecureFolderCard> {
  void _openScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SecureFolderScreen(),
      ),
    );
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

    final mess = ScaffoldMessenger.of(context);
    if (result.failed == 0) {
      mess.showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.imported} file'
            '${result.imported == 1 ? '' : 's'} to secure folder',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } else {
      mess.showSnackBar(
        SnackBar(
          content: Text(
            '${result.imported} imported, ${result.failed} failed',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SecureFolderProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openScreen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _accentColor(context).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        provider.isLocked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        size: 20,
                        color: _accentColor(context),
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
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            provider.isLocked
                                ? 'Tap to open'
                                : '${provider.fileCount} file'
                                    '${provider.fileCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!provider.isLocked)
                      IconButton(
                        icon: Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        tooltip: 'Import files',
                        visualDensity: VisualDensity.compact,
                        onPressed: _showImportDialog,
                      ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.4),
                    ),
                  ],
                ),
                // Live import progress chip — visible even after the dialog is
                // dismissed to background, so the user keeps seeing progress.
                if (provider.isImporting) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: provider.importProgress > 0
                              ? provider.importProgress
                              : null,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Importing ${provider.importCompleted} of '
                          '${provider.importTotal}…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _accentColor(BuildContext context) {
    if (!context.watch<SecureFolderProvider>().isLocked) {
      return Theme.of(context).colorScheme.primary;
    }
    return Theme.of(context).colorScheme.tertiary;
  }
}
