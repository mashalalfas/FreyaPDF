import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:feya_pdf/features/file_management/app_state.dart';
import 'package:feya_pdf/features/security/secure_folder_provider.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';

/// Shows a dialog for importing files into the secure folder.
///
/// Displays non-encrypted files from [AppState] with multi-select checkboxes.
/// On import, each selected file is encrypted and moved to the secure folder.
/// Returns `true` if at least one file was imported.
Future<bool> showSecureFolderImportDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => const _SecureFolderImportDialog(),
  );
  return result ?? false;
}

class _SecureFolderImportDialog extends StatefulWidget {
  const _SecureFolderImportDialog();

  @override
  State<_SecureFolderImportDialog> createState() =>
      _SecureFolderImportDialogState();
}

class _SecureFolderImportDialogState
    extends State<_SecureFolderImportDialog> {
  final Set<String> _selected = {};
  bool _isImporting = false;

  List<PdfFile> _getImportableFiles(AppState appState) {
    return appState.files.where((f) => !f.isEncrypted).toList(growable: false);
  }

  Future<void> _import() async {
    if (_selected.isEmpty) return;

    setState(() => _isImporting = true);

    final provider = context.read<SecureFolderProvider>();
    int successCount = 0;

    for (final path in _selected) {
      final ok = await provider.importFile(path);
      if (ok) successCount++;
    }

    if (mounted) {
      Navigator.pop(context, successCount > 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;
    final files = _getImportableFiles(appState);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(Icons.lock_rounded, color: colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          const Text('Import to Secure Folder'),
        ],
      ),
      content: _isImporting
          ? SizedBox(
              height: 120,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Encrypting and importing...',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SizedBox(
              width: double.maxFinite,
              child: files.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.folder_off_outlined,
                              size: 40,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No files available to import',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add PDFs to your library first',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select files to encrypt and move to the secure folder',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Select all / deselect all row
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _selected.length < files.length
                                  ? () => setState(
                                      () => _selected.addAll(
                                        files.map((f) => f.path),
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.select_all_rounded,
                                  size: 16),
                              label: const Text('Select all'),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                textStyle: const TextStyle(fontSize: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _selected.isNotEmpty
                                  ? () => setState(() => _selected.clear())
                                  : null,
                              icon: const Icon(Icons.deselect_rounded,
                                  size: 16),
                              label: const Text('Clear'),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.onSurfaceVariant,
                                textStyle: const TextStyle(fontSize: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: files.length,
                            itemBuilder: (context, index) {
                              final file = files[index];
                              final isSelected =
                                  _selected.contains(file.path);
                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selected.add(file.path);
                                    } else {
                                      _selected.remove(file.path);
                                    }
                                  });
                                },
                                title: Text(
                                  file.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: Text(
                                  file.sizeFormatted,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
      actions: _isImporting
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    _selected.isEmpty ? null : _import,
                child: Text(
                  _selected.isEmpty
                      ? 'Import'
                      : 'Import (${_selected.length})',
                ),
              ),
            ],
    );
  }
}
