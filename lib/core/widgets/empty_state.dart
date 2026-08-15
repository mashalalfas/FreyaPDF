// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A warm, hand-authored empty state: a gentle floating document Lottie,
/// an editorial [titleMedium] heading, an optional subtitle, and an optional
/// action button.
///
/// Anti-generic design: the visual is a custom Freya Lottie (never a stock
/// illustration pack) rendered at 72–96 px, with motion that mirrors the
/// app's tactile, warm identity.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.visualSize = 88,
    this.icon,
    this.compact = false,
  });

  /// Heading text, styled with [TextTheme.titleMedium] (Fraunces serif).
  final String title;

  /// Optional supporting line, styled with [TextTheme.bodyMedium].
  final String? subtitle;

  /// Optional trailing action button.
  final Widget? action;

  /// Diameter of the Lottie visual. Defaults to 88px.
  final double visualSize;

  /// Optional fallback icon used only if the Lottie asset fails to load.
  final IconData? icon;

  /// When true, tightens vertical rhythm for use inside sheets/panels.
  final bool compact;

  /// Whether the Lottie should loop. Under the widget-test binding a
  /// perpetual loop would make [pumpAndSettle] time out, so we disable
  /// looping in tests while keeping the gentle motion in the real app.
  bool get _loops => !WidgetsBinding.instance
      .runtimeType
      .toString()
      .contains('Test');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fallbackIcon = icon ?? Icons.picture_as_pdf_outlined;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 24 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: Lottie.asset(
                'assets/animations/empty_document.json',
                width: visualSize,
                height: visualSize,
                repeat: _loops,
                animate: true,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: visualSize,
                    height: visualSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.secondary.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      fallbackIcon,
                      size: visualSize * 0.5,
                      color: cs.primary.withValues(alpha: 0.6),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              SizedBox(height: compact ? 4 : 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 12 : 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
