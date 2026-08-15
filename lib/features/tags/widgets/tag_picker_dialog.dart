// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/tags/tag.dart';
import 'package:freya_pdf/features/tags/tag_provider.dart';
import 'package:freya_pdf/features/tags/widgets/tag_chip.dart';

/// Show a multi-select dialog for tagging a single file.
///
/// Returns `true` if the user applied changes, `false` (or `null`) if
/// cancelled. New tags can be created inline via "+ New tag".
Future<bool?> showTagPickerDialog(
  BuildContext context, {
  required String filePath,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TagPickerSheet(filePath: filePath),
  );
}

class _TagPickerSheet extends StatefulWidget {
  final String filePath;
  const _TagPickerSheet({required this.filePath});

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    final tagProvider = context.read<TagProvider>();
    _selected = tagProvider.getTagsForFile(widget.filePath).toSet();
  }

  void _toggle(String tagId) {
    setState(() {
      if (_selected.contains(tagId)) {
        _selected.remove(tagId);
      } else {
        _selected.add(tagId);
      }
    });
  }

  Future<void> _createInline() async {
    final created = await showDialog<Tag>(
      context: context,
      builder: (_) => const _TagEditDialog(),
    );
    if (created != null && mounted) {
      setState(() => _selected.add(created.id));
    }
  }

  Future<void> _apply() async {
    await context
        .read<TagProvider>()
        .setFileTags(widget.filePath, _selected.toList());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final tagProvider = context.watch<TagProvider>();
    final tags = tagProvider.tags;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.label_outline_rounded,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Tag file',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select tags to apply. Tap a tag to toggle.',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (tags.isEmpty)
              _emptyState(context)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    TagChip(
                      tag: tag,
                      selected: _selected.contains(tag.id),
                      onTap: () => _toggle(tag.id),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _createInline,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New tag'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.primary,
                side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _apply,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.label_off_outlined,
            size: 28,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 6),
          Text(
            'No tags yet',
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Create your first tag below',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable create/edit dialog. Returns the saved [Tag] on success.
Future<Tag?> showTagEditDialog(
  BuildContext context, {
  Tag? existing,
}) {
  return showDialog<Tag>(
    context: context,
    builder: (_) => _TagEditDialog(existing: existing),
  );
}

class _TagEditDialog extends StatefulWidget {
  final Tag? existing;
  const _TagEditDialog({this.existing});

  @override
  State<_TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<_TagEditDialog> {
  late final TextEditingController _nameController;
  late int _color;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _color = widget.existing?.color ?? Tag.defaultColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final tagProvider = context.read<TagProvider>();
    Tag? result;
    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(name: name, color: _color);
      await tagProvider.updateTag(updated);
      result = updated;
    } else {
      result = await tagProvider.createTag(name: name, color: _color);
    }
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.existing == null ? 'New tag' : 'Edit tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
              hintText: 'e.g. Work, Personal',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Text(
            'COLOR',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _ColorPickerGrid(
            selected: _color,
            onSelected: (c) => setState(() => _color = c),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// Simple grid of preset colors for the tag editor.
class _ColorPickerGrid extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const _ColorPickerGrid({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in Tag.palette)
          _ColorSwatch(
            color: c,
            isSelected: c == selected,
            onTap: () => onSelected(c),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final int color;
  final bool isSelected;
  final VoidCallback onTap;
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Color(color).withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? Icon(
                Icons.check_rounded,
                size: 18,
                color: Tag.contrastFor(color),
              )
            : null,
      ),
    );
  }
}
