import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/highlights/highlight.dart';
import 'package:freya_pdf/features/highlights/highlight_provider.dart';

/// A bottom-drawer panel that lists all highlights for the current file.
///
/// Shows each highlight's page number, excerpt, and a delete button.
/// Tapping a highlight navigates to the page (via callback).
class HighlightsPanel extends StatelessWidget {
  const HighlightsPanel({
    super.key,
    required this.onNavigateToPage,
    this.onClose,
  });

  /// Callback when user taps a highlight to jump to its page.
  final void Function(int pageNumber) onNavigateToPage;

  /// Optional close callback.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<HighlightProvider>();
    final highlights = provider.fileHighlights;

    // Split highlights by page for organized display
    final byPage = <int, List<HighlightData>>{};
    for (final h in highlights) {
      byPage.putIfAbsent(h.pageNumber, () => []).add(h);
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
                  Icon(Icons.highlight_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Highlights',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (highlights.isNotEmpty) ...[
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
                        '${highlights.length}',
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
            // List of highlights
            if (highlights.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.highlight_off_rounded,
                      size: 36,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.25),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No highlights yet',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select text or draw a rectangle',
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
                    final pageHighlights = byPage[page]!;
                    return _PageHighlightsGroup(
                      pageNumber: page,
                      highlights: pageHighlights,
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

class _PageHighlightsGroup extends StatelessWidget {
  final int pageNumber;
  final List<HighlightData> highlights;
  final void Function(int pageNumber) onNavigateToPage;

  const _PageHighlightsGroup({
    required this.pageNumber,
    required this.highlights,
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
        ...highlights.map(
          (h) => _HighlightTile(
            highlight: h,
            onTap: () => onNavigateToPage(h.pageNumber),
          ),
        ),
      ],
    );
  }
}

class _HighlightTile extends StatelessWidget {
  final HighlightData highlight;
  final VoidCallback onTap;

  const _HighlightTile({
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final highlightColor = Color(highlight.color);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 4,
        height: 32,
        decoration: BoxDecoration(
          color: highlightColor,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      title: highlight.isRectangle
          ? Row(
              children: [
                Icon(
                  Icons.crop_free_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  'Rectangle highlight',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
              ],
            )
          : Text(
              highlight.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface,
              ),
            ),
      subtitle: Text(
        _timeAgo(highlight.createdAt),
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
          context.read<HighlightProvider>().removeHighlight(highlight.id);
        },
      ),
      onTap: onTap,
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
