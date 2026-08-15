// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A vertical speed-dial FAB.
///
/// The collapsed state is a single generic "+" FAB (teal, rounded per the app's
/// `floatingActionButtonTheme`). Tapping it expands a short column of labeled
/// primary actions (File, Folder) upward with a gentle stagger. Expands from an
/// [AnimationController] and nudges selection with a light haptic, matching the
/// app's existing tactile motion (see `app_lock_screen.dart`).
///
/// Each dial action exposes a visible text label and satisfies the ≥48dp tap
/// target. The whole dial is dismissible by tapping the dimmed surface behind
/// it (a [ModalBarrier]) while open.
///
/// Scope guard: the dial stays a *launcher* — File/Folder pickers and the
/// import pipeline live in the caller (HomeScreen), not in this widget.
class FabSpeedDial extends StatefulWidget {
  /// Built-in labeled actions. Custom actions aren't needed for v1; keep the
  /// surface minimal.
  final VoidCallback onPickFile;
  final VoidCallback onPickFolder;

  const FabSpeedDial({
    super.key,
    required this.onPickFile,
    required this.onPickFolder,
  });

  @override
  State<FabSpeedDial> createState() => _FabSpeedDialState();
}

class _FabSpeedDialState extends State<FabSpeedDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  bool get _open =>
      _controller.status == AnimationStatus.forward ||
      _controller.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    // Actions rise up from just below their resting spot; each is staggered in
    // build so the column feels like it unrolls rather than popping all at once.
    _slide = Tween<double>(
      begin: 0.16,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _controller.reverse();
    } else {
      HapticFeedback.selectionClick();
      _controller.forward();
    }
  }

  void _runAction(VoidCallback action) async {
    HapticFeedback.lightImpact();
    await _controller.reverse();
    if (mounted) action();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final open = _open;
        return Stack(
          alignment: Alignment.bottomRight,
          children: [
            // Dim behind the dial while open; tap to collapse.
            if (open)
              Positioned.fill(
                child: ModalBarrier(
                  color: Colors.black.withValues(alpha: 0.1),
                  onDismiss: _controller.reverse,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0, 0.5),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _controller,
                                curve: const Interval(
                                  0,
                                  0.6,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                            ),
                        child: Transform.translate(
                          offset: Offset(0, 12 * _slide.value),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _DialAction(
                                icon: Icons.picture_as_pdf_rounded,
                                label: 'File',
                                onPressed: () => _runAction(widget.onPickFile),
                              ),
                              const SizedBox(height: 10),
                              _DialAction(
                                icon: Icons.folder_open_rounded,
                                label: 'Folder',
                                onPressed: () =>
                                    _runAction(widget.onPickFolder),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                FloatingActionButton(
                  onPressed: _toggle,
                  tooltip: open ? 'Close' : 'Add files',
                  heroTag: 'speed_dial',
                  // The plan: collapsed icon stays a generic "+", always the
                  // trigger.
                  child: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A single labeled dial action. Tap target ≥48dp, `Material`-styling for
/// ripple, warm surface pill echoing the app's snackbar/card language.
class _DialAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _DialAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerLow,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onTap: onPressed,
          child: Tooltip(
            message: label,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
