// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A collapsible search bar that animates in from the top of the viewer.
///
/// Exposes callbacks for search input changes, match navigation, and
/// close. Takes [matchCount] and [currentMatchIndex] as display values
/// (integers) so the parent controller decides the actual match data.
class SearchBarWidget extends StatefulWidget {
  final int matchCount;
  final int currentMatchIndex;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNextMatch;
  final VoidCallback onPreviousMatch;
  final VoidCallback onClose;

  /// Non-null when search cannot run for this document (very large or
  /// image-only). Shown instead of the match counters.
  final String? searchUnavailableReason;

  /// True when the scan stopped early and only a prefix was searched.
  final bool searchTruncated;

  const SearchBarWidget({
    super.key,
    this.matchCount = 0,
    this.currentMatchIndex = 0,
    this.searchUnavailableReason,
    this.searchTruncated = false,
    required this.onSearchChanged,
    required this.onNextMatch,
    required this.onPreviousMatch,
    required this.onClose,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleClose() {
    _controller.clear();
    _focusNode.unfocus();
    widget.onClose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.escape)) {
      _handleClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Focus(
      // TextField owns _focusNode through its internal EditableText Focus
      // widget. The outer Focus must use its own node; attaching the same
      // FocusNode to both widgets corrupts Flutter's focus attachment tree.
      onKeyEvent: _onKeyEvent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            children: [
              // Search icon
              Icon(
                Icons.search_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),

              // Text input field
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: widget.onSearchChanged,
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: cs.onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    hintText: 'Search in document…',
                    hintStyle: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
              ),

              // Search unavailable message (very large / image-only docs)
              if (widget.searchUnavailableReason != null &&
                  _controller.text.isNotEmpty)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      widget.searchUnavailableReason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        fontWeight: FontWeight.w500,
                        color: cs.error,
                      ),
                    ),
                  ),
                ),

              // Match count label
              if (widget.matchCount > 0 &&
                  widget.searchUnavailableReason == null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${widget.currentMatchIndex} / ${widget.matchCount}',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),

              // No matches indicator
              if (_controller.text.isNotEmpty &&
                  widget.matchCount == 0 &&
                  widget.searchUnavailableReason == null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'No results',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: cs.error,
                    ),
                  ),
                ),

              // Truncated-scan hint
              if (widget.searchTruncated &&
                  widget.matchCount > 0 &&
                  widget.searchUnavailableReason == null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Matches limited — refine query',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),

              // Previous match arrow
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous match',
                onPressed: widget.matchCount > 0 ? widget.onPreviousMatch : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),

              // Next match arrow
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: 'Next match',
                onPressed: widget.matchCount > 0 ? widget.onNextMatch : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),

              const SizedBox(width: 4),

              // Close button
              IconButton(
                icon: const Icon(Icons.close_rounded),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Close search',
                onPressed: _handleClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
