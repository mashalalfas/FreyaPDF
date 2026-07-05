import 'package:flutter/material.dart';
import 'package:feya_pdf/features/tags/tag.dart';

/// Material-3 style chip for a [Tag].
///
/// Two visual modes:
///   * [compact]  — small, used in horizontal filter bar and tile overlays
///   * full       — larger, used in tag management lists and picker dialogs
///
/// [selected] toggles between "inactive" (tinted background) and
/// "selected" (solid color background) variants. This is the same visual
/// language as Material You's filter chips.
class TagChip extends StatelessWidget {
  final Tag tag;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDeleted;
  final IconData? trailingIcon;

  const TagChip({
    super.key,
    required this.tag,
    this.selected = false,
    this.compact = false,
    this.onTap,
    this.onLongPress,
    this.onDeleted,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final tagColor = tag.displayColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final height = compact ? 28.0 : 32.0;
    final fontSize = compact ? 11.5 : 13.0;
    final hPad = compact ? 10.0 : 12.0;
    final dotSize = compact ? 6.0 : 7.0;

    final Color background;
    final Color border;
    final Color foreground;

    if (selected) {
      background = tagColor;
      border = tagColor;
      foreground = Tag.contrastFor(tag.color);
    } else {
      // Tinted background — works on both light and dark.
      background = isDark
          ? tagColor.withValues(alpha: 0.18)
          : tagColor.withValues(alpha: 0.12);
      border = tagColor.withValues(alpha: isDark ? 0.45 : 0.35);
      foreground = isDark
          ? tagColor.withValues(alpha: 0.92)
          : Color.lerp(tagColor, Colors.black, 0.25) ?? tagColor;
    }

    return Material(
      color: background,
      shape: StadiumBorder(side: BorderSide(color: border, width: 1)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Color dot — only in compact mode (full mode uses border+bg).
              if (compact) ...[
                Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: selected
                        ? Tag.contrastFor(tag.color).withValues(alpha: 0.85)
                        : tagColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                    letterSpacing: 0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trailingIcon, size: compact ? 14 : 16, color: foreground),
              ],
              if (onDeleted != null) ...[
                const SizedBox(width: 2),
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onDeleted,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: compact ? 14 : 16,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A pure visual dot — used in file list tiles where space is tight.
class TagDot extends StatelessWidget {
  final Tag tag;
  final double size;
  const TagDot({super.key, required this.tag, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tag.displayColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1.2,
        ),
      ),
    );
  }
}
