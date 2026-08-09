import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/encryption/passphrase_strength.dart';

/// Shows a dialog to set/view/change the session passphrase.
/// Returns true if passphrase was set, false if cancelled.
Future<bool> showPassphraseDialog(BuildContext context) async {
  final controller = TextEditingController();
  bool obscure = true;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final text = controller.text;
          final strength = calculateStrength(text);
          final isCommon =
              text.length >= 8 && isCommonPassword(text);
          final isValid = text.length >= 8 && !isCommon;
          final colorScheme = Theme.of(ctx).colorScheme;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.lock_rounded,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Text('Session Passphrase'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Used to encrypt/decrypt PDFs. '
                  'Not stored on disk — only held in memory.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: obscure,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Enter passphrase',
                    prefixIcon: const Icon(Icons.vpn_key_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  onSubmitted: (_) {
                    if (isValid) {
                      Navigator.pop(ctx, true);
                    }
                  },
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // Strength meter bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: strengthFill(strength),
                      ),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      builder: (_, value, child) {
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor:
                              colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            strengthColor(strength, colorScheme),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        strength == PassphraseStrength.weak
                            ? Icons.warning_amber_rounded
                            : strength == PassphraseStrength.veryStrong
                                ? Icons.verified_rounded
                                : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: strengthColor(strength, colorScheme),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        strengthLabel(strength),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: strengthColor(strength, colorScheme),
                        ),
                      ),
                      if (isCommon) ...[
                        const Spacer(),
                        Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Common password',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (text.isNotEmpty && text.length < 8) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Minimum 8 characters required',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (isCommon) ...[
                  const SizedBox(height: 6),
                  Text(
                    'This is a commonly used password. Please choose a stronger one.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '⚠️ If you forget this, encrypted PDFs cannot be recovered.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isValid
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Set'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true && controller.text.isNotEmpty) {
    if (context.mounted) {
      // Capture provider before any further work — provider is app-scoped
      // so this is safe, but we still early-out if the calling context
      // has gone away so the caller doesn't think the passphrase was
      // applied when it wasn't.
      final encryption = context.read<EncryptionProvider>();
      encryption.setPassphrase(controller.text);
      controller.dispose();
      return true;
    }
    controller.dispose();
    return false;
  }
  controller.dispose();
  return false;
}
