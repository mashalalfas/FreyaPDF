// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';

/// A lightweight animated progress dialog shown while encryption runs so the
/// UI never looks static/frozen during a (possibly slow) encrypt operation.
///
/// [fileName] is shown in the indeterminate subtitle (e.g. "Encrypting report.pdf…").
/// When [total] is provided, the subtitle shows a live "Encrypting X of N…"
/// update driven by [updateEncryptingProgress] from the batch callback. If
/// [total] is null the dialog is purely indeterminate (pulsing lock + spinner).
Future<void> showEncryptingProgressDialog(
  BuildContext context, {
  required String fileName,
  int? total,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EncryptingProgressDialog(fileName: fileName, total: total),
  );
}

/// Updates the currently-open encrypting progress dialog (if any) with a new
/// "X of N" count. Safe no-op if no such dialog is open.
void updateEncryptingProgress(BuildContext context, int completed) {
  _EncryptingProgressDialogState._activeController.updateCount(completed);
}

/// Closes the currently-open encrypting progress dialog (if any) with `true`.
/// Safe no-op if no such dialog is open.
void closeEncryptingProgressDialog(BuildContext context) {
  _EncryptingProgressDialogState._activeController.close();
}

class _EncryptingProgressDialog extends StatefulWidget {
  final String fileName;
  final int? total;

  const _EncryptingProgressDialog({required this.fileName, this.total});

  @override
  State<_EncryptingProgressDialog> createState() =>
      _EncryptingProgressDialogState();
}

class _EncryptingProgressDialogController {
  _EncryptingProgressDialogState? _state;
  void attach(_EncryptingProgressDialogState s) => _state = s;
  void detach() => _state = null;
  void updateCount(int completed) => _state?.updateCount(completed);
  void close() => _state?.close();
}

class _EncryptingProgressDialogState extends State<_EncryptingProgressDialog>
    with SingleTickerProviderStateMixin {
  static final _EncryptingProgressDialogController _activeController =
      _EncryptingProgressDialogController();

  late final AnimationController _pulse;
  int _completed = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _activeController.attach(this);
  }

  @override
  void dispose() {
    _activeController.detach();
    _pulse.dispose();
    super.dispose();
  }

  void updateCount(int completed) {
    if (!mounted || completed == _completed) return;
    setState(() => _completed = completed);
  }

  void close() {
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasProgress = widget.total != null && widget.total! > 0;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) =>
                    Transform.scale(scale: _pulse.value, child: child),
                child: Icon(
                  Icons.lock_rounded,
                  size: 42,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                hasProgress
                    ? 'Encrypting $_completed of ${widget.total}…'
                    : 'Encrypting ${widget.fileName}…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              if (!hasProgress) ...[
                const SizedBox(height: 4),
                Text(
                  widget.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: colorScheme.onSurfaceVariant,
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
