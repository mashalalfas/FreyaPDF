// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';

/// Shows a dialog for importing files into the secure folder.
///
/// Displays non-encrypted files from [AppState] with multi-select checkboxes.
/// On import, the batch is owned by [SecureFolderProvider] (survives dismissal),
/// the dialog renders live progress, and returns `true` if an import batch was
/// started (import may still be running in the background after return).
/// Returns `false`/`null` if the user cancelled before importing anything.
Future<bool> showSecureFolderImportDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => const _SecureFolderImportDialog(),
  );
  return result ?? false;
}

class _SecureFolderImportDialog extends StatefulWidget {
  const _SecureFolderImportDialog();

  @override
  State<_SecureFolderImportDialog> createState() =>
      _SecureFolderImportDialogState();
}

class _SecureFolderImportDialogState
    extends State<_SecureFolderImportDialog> {
  final Set<String> _selected = {};

  /// Track whether this dialog instance started a batch (so we can auto-close
  /// when the provider finishes even if we were dismissed via `didChangeDependencies`).
  bool _started = false;

  /// Cancellation token so the auto-close listener ignores batches started by
  /// a newer instance of this dialog.
  Object _batch = Object();

  List<PdfFile> _getImportableFiles(AppState appState) {
    return appState.files.where((f) => !f.isEncrypted).toList(growable: false);
  }

  void _startImport() {
    if (_selected.isEmpty) return;
    final provider = context.read<SecureFolderProvider>();
    final batch = Object();
    _batch = batch;
    _started = true;
    setState(() {});

    // Fire the batch onto the provider (it owns the loop, so this survives this
    // dialog being dismissed to background). When it completes, auto-close if
    // we are still mounted and this dialog is the one that started the batch.
    // A short pause lets the lock→checkmark completion animation play before pop.
    provider.importFiles(_selected.toList()).then((result) async {
      if (mounted && identical(_batch, batch) && !provider.isImporting) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (mounted && identical(_batch, batch)) {
          Navigator.of(context).pop(true);
        }
      }
    });
  }

  void _runInBackground() {
    // The provider already owns the running batch; dismissing the dialog keeps
    // it going. The caller (card) detects the import started via the provider's
    // generation counter and awaits provider.activeImport for the summary.
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final provider = context.watch<SecureFolderProvider>();
    final isImporting = provider.isImporting && _started;
    final colorScheme = Theme.of(context).colorScheme;
    final files = _getImportableFiles(appState);

    return AlertDialog(
      // Barrier-dismissible while importing so the user can drop the dialog and
      // let the batch continue in the background. The provider owns the batch;
      // dismissal never aborts it.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(Icons.lock_rounded, color: colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Import to Secure Folder',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: isImporting
          ? _ImportProgress(
              key: ValueKey(_batch),
              completed: provider.importCompleted,
              total: provider.importTotal,
              progress: provider.importProgress,
              currentFileName: provider.importCurrentFileName,
              color: colorScheme.primary,
            )
          : SizedBox(
              width: double.maxFinite,
              child: files.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.folder_off_outlined,
                              size: 40,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No files available to import',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add PDFs to your library first',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select files to encrypt and move to the secure folder',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _selected.length < files.length
                                  ? () => setState(
                                      () => _selected.addAll(
                                        files.map((f) => f.path),
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.select_all_rounded,
                                  size: 16),
                              label: const Text('Select all'),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                textStyle: const TextStyle(fontSize: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _selected.isNotEmpty
                                  ? () => setState(() => _selected.clear())
                                  : null,
                              icon: const Icon(Icons.deselect_rounded,
                                  size: 16),
                              label: const Text('Clear'),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.onSurfaceVariant,
                                textStyle: const TextStyle(fontSize: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: files.length,
                            itemBuilder: (context, index) {
                              final file = files[index];
                              final isSelected =
                                  _selected.contains(file.path);
                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selected.add(file.path);
                                    } else {
                                      _selected.remove(file.path);
                                    }
                                  });
                                },
                                title: Text(
                                  file.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: Text(
                                  file.sizeFormatted,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
      actions: isImporting
          ? [
              // Keep the batch going, dismiss the dialog; the card surfaces a
              // completion summary once the provider finishes.
              TextButton.icon(
                onPressed: _runInBackground,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Run in background'),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                ),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    _selected.isEmpty ? null : _startImport,
                child: Text(
                  _selected.isEmpty
                      ? 'Import'
                      : 'Import (${_selected.length})',
                ),
              ),
            ],
    );
  }
}

/// Animated per-file progress: a lock with a circular fill that advances as each
/// file completes, morphing to a full ring + checkmark on completion.
/// Lightweight, no dependencies — built from a [CustomPainter] + [AnimationController].
class _ImportProgress extends StatefulWidget {
  final int completed;
  final int total;
  final double progress;
  final String? currentFileName;
  final Color color;

  const _ImportProgress({
    super.key,
    required this.completed,
    required this.total,
    required this.progress,
    required this.currentFileName,
    required this.color,
  });

  @override
  State<_ImportProgress> createState() => _ImportProgressState();
}

class _ImportProgressState extends State<_ImportProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _from = 0;

  bool get _done => widget.completed >= widget.total && widget.total > 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..value = widget.progress.clamp(0.0, 1.0);
    _from = _controller.value;
  }

  @override
  void didUpdateWidget(_ImportProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_done) {
      // Batch complete: spring the arc to full so the checkmark can reveal.
      _controller.animateTo(
        1.0,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutBack,
      );
    } else if (widget.progress != _controller.value) {
      // Advance the arc toward the new per-file progress.
      _from = _controller.value;
      _controller.animateTo(
        widget.progress.clamp(0.0, 1.0),
        duration: Duration(
          milliseconds: (180 + (widget.progress - _from).abs() * 360).round(),
        ),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = widget.color;
    final detailColor = colorScheme.onSurfaceVariant;

    return SizedBox(
      width: 240,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _LockFillPainter(
                    progress: _controller.value,
                    done: _done,
                    color: color,
                    trackColor: color.withValues(alpha: 0.15),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _done
                ? 'Encrypted ${widget.total} of ${widget.total}'
                : 'Encrypting ${widget.completed + 1} of ${widget.total}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.currentFileName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: detailColor),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: widget.progress,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a lock silhouette with a circular progress arc that fills per file,
/// morphing to a full ring + checkmark once the batch is done.
class _LockFillPainter extends CustomPainter {
  final double progress;
  final bool done;
  final Color color;
  final Color trackColor;

  _LockFillPainter({
    required this.progress,
    required this.done,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: r);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final twoPi = 2 * pi;

    // Track ring.
    paint.color = trackColor;
    canvas.drawArc(rect, -pi / 2, twoPi, false, paint);

    // Progress arc (fills clockwise from top).
    paint.color = color;
    final sweep = twoPi * progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, -pi / 2, sweep, false, paint);

    _paintLock(canvas, center, color);

    // On completion, overlay a checkmark (revealed as progress nears 1).
    if (done && progress >= 0.99) {
      _paintCheckmark(canvas, center, color, progress);
    }
  }

  void _paintLock(Canvas canvas, Offset c, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Shackle (arc above the body).
    canvas.drawArc(
      Rect.fromCircle(center: Offset(c.dx, c.dy - 6), radius: 9),
      pi,
      pi,
      false,
      paint,
    );

    // Body.
    final body = RRect.fromRectAndCorners(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + 8),
        width: 24,
        height: 18,
      ),
      topLeft: const Radius.circular(4),
      topRight: const Radius.circular(4),
      bottomLeft: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(body, paint);

    // Keyhole.
    canvas.drawCircle(Offset(c.dx, c.dy + 8), 2, Paint()..color = color);
  }

  void _paintCheckmark(Canvas canvas, Offset c, Color color, double t) {
    final fade = Curves.easeOut.transform(((t - 0.99) / 0.01).clamp(0.0, 1.0));
    final paint = Paint()
      ..color = color.withValues(alpha: fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(c.dx - 9, c.dy + 1)
      ..lineTo(c.dx - 3, c.dy + 7)
      ..lineTo(c.dx + 9, c.dy - 6);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LockFillPainter old) =>
      old.progress != progress || old.done != done || old.color != color;
}

