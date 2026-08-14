// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/tags/tag.dart';
import 'package:freya_pdf/features/tags/widgets/tag_chip.dart';

class FileListTile extends StatelessWidget {
  final PdfFile file;
  final List<Tag> tags;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onEncrypt;
  final VoidCallback? onDecrypt;
  final VoidCallback? onTag;
  final int? bookmarkCount;
  final double? progressValue;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;
  final bool isSelectionMode;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onEnterSelectionMode; // overrides context menu when set

  const FileListTile({
    super.key,
    required this.file,
    this.tags = const [],
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onShare,
    this.onEncrypt,
    this.onDecrypt,
    this.onTag,
    this.bookmarkCount,
    this.progressValue,
    this.isFavorite = false,
    this.onToggleFavorite,
    this.isSelectionMode = false,
    this.onSelectToggle,
    this.onEnterSelectionMode,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectionAlpha = isDark ? 0.20 : 0.15;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: selectionAlpha)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border(left: BorderSide(color: colorScheme.primary, width: 4))
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
          onTap: isSelectionMode ? onSelectToggle : onTap,
          onLongPress: onEnterSelectionMode ?? (isSelectionMode ? null : () => _showContextMenu(context)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isSelectionMode)
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => onSelectToggle?.call(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                else
                  Hero(
                    tag: 'file-icon-${file.path}',
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isSelected ? Icons.picture_as_pdf_rounded : Icons.description_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.displayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            file.modifiedFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.data_usage_rounded,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            file.sizeFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                      if (progressValue != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(1.5),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 3,
                            backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                          ),
                        ),
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _TagRow(tags: tags),
                      ],
                      if ((bookmarkCount ?? 0) > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.bookmark_rounded,
                              size: 13,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${bookmarkCount ?? 0}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (onToggleFavorite != null && !isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: GestureDetector(
                          onTap: onToggleFavorite,
                          child: Icon(
                            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                            size: 18,
                            color: isFavorite
                                ? colorScheme.secondary
                                : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    if (!isSelectionMode)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                file.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(),
            if (onShare != null)
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(ctx);
                  onShare?.call();
                },
              ),
            if (onEncrypt != null && !file.isEncrypted)
              ListTile(
                leading: Icon(
                  Icons.lock_outline_rounded,
                  color: Theme.of(ctx).colorScheme.tertiary,
                ),
                title: const Text('Encrypt'),
                onTap: () {
                  Navigator.pop(ctx);
                  onEncrypt?.call();
                },
              ),
            if (onDecrypt != null && file.isEncrypted)
              ListTile(
                leading: Icon(
                  Icons.lock_open_rounded,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: const Text('Decrypt to plain'),
                onTap: () {
                  Navigator.pop(ctx);
                  onDecrypt?.call();
                },
              ),
            ListTile(
              leading: Icon(
                Icons.label_outline_rounded,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: const Text('Tag'),
              trailing: tags.isEmpty
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _TagDotsRow(tags: tags, max: 3),
                    ),
              onTap: () {
                Navigator.pop(ctx);
                onTag?.call();
              },
            ),
            if (onDelete != null)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                title: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('Permanently delete "${file.name}"?\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call();
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Inline row of colored tag dots, with overflow handling.
class _TagRow extends StatelessWidget {
  final List<Tag> tags;
  const _TagRow({required this.tags});

  static const int _maxVisible = 4;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
    final visible = tags.length > _maxVisible
        ? tags.sublist(0, _maxVisible - 1)
        : tags;
    final hiddenCount = tags.length - visible.length;

    return Row(
      children: [
        for (final tag in visible) ...[
          TagDot(tag: tag, size: 7),
          const SizedBox(width: 4),
        ],
        if (hiddenCount > 0) ...[
          Text(
            '+$hiddenCount',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Variant of the dots row used in the context menu.
class _TagDotsRow extends StatelessWidget {
  final List<Tag> tags;
  final int max;
  const _TagDotsRow({required this.tags, this.max = 3});

  @override
  Widget build(BuildContext context) {
    final visible = tags.length > max ? tags.sublist(0, max) : tags;
    final hidden = tags.length - visible.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tag in visible) ...[
          TagDot(tag: tag, size: 8),
          const SizedBox(width: 4),
        ],
        if (hidden > 0)
          Text(
            '+$hidden',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
