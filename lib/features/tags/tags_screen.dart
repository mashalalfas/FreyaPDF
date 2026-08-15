// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/core/widgets/freya_snack_bar.dart';
import 'package:freya_pdf/features/tags/tag.dart';
import 'package:freya_pdf/features/tags/tag_provider.dart';
import 'package:freya_pdf/features/tags/widgets/tag_chip.dart';
import 'package:freya_pdf/features/tags/widgets/tag_picker_dialog.dart';

/// Full tag management screen — list, create, edit, delete.
class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tagProvider = context.watch<TagProvider>();
    final tags = tagProvider.tags;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags'),
      ),
      body: tags.isEmpty
          ? _emptyState(context, colorScheme)
          : ListView.separated(
              padding: const EdgeInsets.only(top: 4, bottom: 96),
              itemCount: tags.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
              itemBuilder: (context, index) {
                final tag = tags[index];
                final count = tagProvider.countFilesWithTag(tag.id);
                return _TagListTile(tag: tag, fileCount: count);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showTagEditDialog(context);
          if (created != null && context.mounted) {
            FreyaSnackBar.show(context, 'Tag "${created.name}" created');
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('New tag'),
      ),
    );
  }

  Widget _emptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.label_outline_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No tags yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create tags to organize your PDFs by category',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagListTile extends StatelessWidget {
  final Tag tag;
  final int fileCount;
  const _TagListTile({required this.tag, required this.fileCount});

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text(
          'Delete "${tag.name}"? It will be removed from $fileCount ${fileCount == 1 ? "file" : "files"}.',
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
    if (confirmed == true && context.mounted) {
      await context.read<TagProvider>().deleteTag(tag.id);
      if (context.mounted) {
        FreyaSnackBar.show(context, 'Tag "${tag.name}" deleted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tag.displayColor.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: TagDot(tag: tag, size: 14),
        ),
      ),
      title: Text(
        tag.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        fileCount == 0
            ? 'No files'
            : '$fileCount file${fileCount == 1 ? '' : 's'}',
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Wrap(
        spacing: 0,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Edit',
            onPressed: () => showTagEditDialog(context, existing: tag),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: colorScheme.error.withValues(alpha: 0.85),
            ),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      onTap: () => showTagEditDialog(context, existing: tag),
    );
  }
}
