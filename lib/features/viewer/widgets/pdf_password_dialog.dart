// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';

class PdfPasswordPromptResult {
  const PdfPasswordPromptResult({
    required this.password,
    required this.remember,
  });

  final String password;
  final bool remember;
}

/// Ask for a password for a standard PDF, optionally remembering it for the
/// current file in secure storage.
Future<PdfPasswordPromptResult?> showPdfPasswordDialog(
  BuildContext context, {
  bool isRetry = false,
}) {
  return showDialog<PdfPasswordPromptResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PdfPasswordDialog(isRetry: isRetry),
  );
}

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog({required this.isRetry});

  final bool isRetry;

  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final _controller = TextEditingController();
  bool _remember = false;
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    Navigator.of(
      context,
    ).pop(PdfPasswordPromptResult(password: password, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('PDF password required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isRetry
                ? 'That password was not accepted. Try again.'
                : 'Enter the password for this PDF to open it.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _remember,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Remember password for this file'),
            subtitle: const Text('Stored securely on this device'),
            onChanged: (value) => setState(() => _remember = value ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Open')),
      ],
    );
  }
}
