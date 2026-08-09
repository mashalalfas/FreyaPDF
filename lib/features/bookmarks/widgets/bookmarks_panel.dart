// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/bookmarks/bookmark.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_provider.dart';

/// A bottom-drawer panel that lists all bookmarks for the current file.
///
/// Shows bookmarks grouped by page, each with page number, label,
/// and creation time. Tapping a bookmark navigates to the page (via callback).
class BookmarksPanel extends StatelessWidget {
  const BookmarksPanel({
    super.key,
    required this.onNavigateToPage,
    this.onClose,
  });

  /// Callback when user taps a bookmark to jump to its page.
  final void Function(int pageNumber) onNavigateToPage;

  /// Optional close callback.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<BookmarkProvider>();
    final bookmarks = provider.fileBookmarks;

    // Split bookmarks by page for organized display
    final byPage = <int, List<Bookmark>>{};
    for (final b in bookmarks) {
      byPage.putIfAbsent(b.pageNumber, () => []).add(b);
    }
    final sortedPages = byPage.keys.toList()..sort();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.bookmark_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Bookmarks',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (bookmarks.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${bookmarks.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      provider.setShowPanel(!provider.showPanel);
                      onClose?.call();
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Close'),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
            // List of bookmarks
            if (bookmarks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.bookmark_border_rounded,
                      size: 36,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.25),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No bookmarks yet',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap the bookmark icon to add one',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: sortedPages.length,
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    final page = sortedPages[index];
                    final pageBookmarks = byPage[page]!;
                    return _PageBookmarksGroup(
                      pageNumber: page,
                      bookmarks: pageBookmarks,
                      onNavigateToPage: onNavigateToPage,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PageBookmarksGroup extends StatelessWidget {
  final int pageNumber;
  final List<Bookmark> bookmarks;
  final void Function(int pageNumber) onNavigateToPage;

  const _PageBookmarksGroup({
    required this.pageNumber,
    required this.bookmarks,
    required this.onNavigateToPage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            'Page $pageNumber',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        ...bookmarks.map(
          (b) => _BookmarkTile(
            bookmark: b,
            onTap: () => onNavigateToPage(b.pageNumber),
          ),
        ),
      ],
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final VoidCallback onTap;

  const _BookmarkTile({
    required this.bookmark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 4,
        height: 32,
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      title: Text(
        bookmark.label ?? 'Page ${bookmark.pageNumber}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        _timeAgo(bookmark.createdAt),
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
      trailing: IconButton(
        icon: Icon(
          Icons.delete_outline_rounded,
          size: 18,
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        onPressed: () {
          context.read<BookmarkProvider>().removeBookmark(bookmark.id);
        },
      ),
      onTap: onTap,
      onLongPress: () => _showRenameDialog(context),
    );
  }

  void _showRenameDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _RenameBookmarkDialog(bookmark: bookmark),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

/// Stateful dialog that owns its TextEditingController so it gets disposed
/// when the dialog closes. Fixes a memory leak where the controller was
/// created in a stateless helper and never released.
class _RenameBookmarkDialog extends StatefulWidget {
  final Bookmark bookmark;
  const _RenameBookmarkDialog({required this.bookmark});

  @override
  State<_RenameBookmarkDialog> createState() => _RenameBookmarkDialogState();
}

class _RenameBookmarkDialogState extends State<_RenameBookmarkDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.bookmark.label ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename bookmark'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Enter label…',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) {
          final label = value.trim();
          if (label.isNotEmpty) {
            context
                .read<BookmarkProvider>()
                .renameBookmark(widget.bookmark.id, label);
          }
          Navigator.of(context).pop();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _controller.text.trim();
            if (label.isNotEmpty) {
              context
                  .read<BookmarkProvider>()
                  .renameBookmark(widget.bookmark.id, label);
            }
            Navigator.of(context).pop();
          },
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
