// Copyright (c) 2026 Freya. All rights reserved.
//
// Floating zoom controls overlay for the PDF reader.
//
// User feedback (HMD Skyline, FreyaPDF v1.2.0+6):
//   * big files open/zoom off-centre to the right (right third hidden)
//   * pinch-zooming feels inverted and drifts the page off-centre
//
// The adopted fix is a small, unobtrusive zoom control that expands from a
// single floating button into a mini row of three actions: zoom in (+),
// zoom out (−) and reset / centre (⤢). Each action is wired to the same
// viewport-centre-anchored zoom mechanism the reader uses, so every step
// keeps the page centred and never lets a page edge drift out of view.
// See lib/features/viewer/pdf_zoom_math.dart for the pure math.

import 'package:flutter/material.dart';

/// Material-style floating zoom control for the reader.
///
/// Collapsed it is a single circular button showing a zoom icon. Tapping it
/// expands a small pill of three tappable actions. Tapping the button again
/// (or the chevron) collapses it. It is intentionally small and tinted with
/// the theme's surface colours so it does not obscure the page.
class ReaderZoomControls extends StatefulWidget {
  const ReaderZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  /// Action invoked when the user presses the zoom-in (＋) button.
  final VoidCallback onZoomIn;

  /// Action invoked when the user presses the zoom-out (−) button.
  final VoidCallback onZoomOut;

  /// Action invoked when the user presses the reset/centre (⤢) button.
  final VoidCallback onReset;

  @override
  State<ReaderZoomControls> createState() => _ReaderZoomControlsState();
}

class _ReaderZoomControlsState extends State<ReaderZoomControls> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  void _fire(VoidCallback action) {
    action();
    // Keep the row open so the user can re-tap repeatedly (multiple zoom
    // steps) without re-expanding each time.
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        alignment: Alignment.centerRight,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: _expanded
          ? _CompactActionRow(
              key: const ValueKey('row'),
              colorScheme: cs,
              onZoomIn: () => _fire(widget.onZoomIn),
              onZoomOut: () => _fire(widget.onZoomOut),
              onReset: () => _fire(widget.onReset),
              onCollapse: _toggleExpanded,
            )
          : _FloatingZoomButton(
              key: const ValueKey('button'),
              colorScheme: cs,
              onPressed: _toggleExpanded,
            ),
    );
  }
}

/// The collapsed single floating button (shows the zoom glyph).
class _FloatingZoomButton extends StatelessWidget {
  const _FloatingZoomButton({
    super.key,
    required this.colorScheme,
    required this.onPressed,
  });

  final ColorScheme colorScheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.surfaceContainerHighest,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.zoom_in_rounded,
            size: 24,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The expanded mini row: (−), (reset ⤢), (+) with a chevron to collapse.
class _CompactActionRow extends StatelessWidget {
  const _CompactActionRow({
    super.key,
    required this.colorScheme,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onCollapse,
  });

  final ColorScheme colorScheme;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.surfaceContainerHighest,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _roundAction(
              tooltip: 'Zoom out',
              icon: Icons.remove_rounded,
              onPressed: onZoomOut,
            ),
            const SizedBox(width: 2),
            _roundAction(
              tooltip: 'Reset / centre page',
              icon: Icons.center_focus_strong_rounded,
              onPressed: onReset,
            ),
            const SizedBox(width: 2),
            _roundAction(
              tooltip: 'Zoom in',
              icon: Icons.add_rounded,
              onPressed: onZoomIn,
            ),
            const SizedBox(width: 2),
            _roundAction(
              tooltip: 'Collapse',
              icon: Icons.chevron_right_rounded,
              onPressed: onCollapse,
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
