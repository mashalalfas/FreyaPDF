// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/security/biometric_auth_service.dart';
import 'package:freya_pdf/features/security/biometric_passphrase_storage.dart';
import 'package:freya_pdf/features/encryption/passphrase_strength.dart';

/// Shows a biometric unlock dialog with fallback to passphrase entry.
///
/// Flow:
/// 1. If biometrics are available → prompt biometric auth
/// 2. If biometrics succeed → retrieve stored passphrase, decrypt
/// 3. If biometrics fail/unavailable → show passphrase input
/// 4. User enters passphrase → stores it for next biometric unlock
///
/// Returns `true` if authenticated (biometric or passphrase), `false` if cancelled.
Future<bool> showBiometricUnlockDialog(BuildContext context) async {
  final encryption = context.read<EncryptionProvider>();

  // Passphrase already set in memory — no auth needed
  if (encryption.hasPassphrase) return true;

  final service = BiometricAuthService();
  final canAuth = await service.canAuthenticate();
  final storage = BiometricPassphraseStorage();

  // Try biometric first
  if (canAuth && context.mounted) {
    final authenticated = await _attemptBiometrics(context, service);
    if (authenticated && context.mounted) {
      // Biometrics succeeded — check for stored passphrase
      final stored = await storage.read();
      if (stored != null && stored.isNotEmpty) {
        encryption.setPassphrase(stored);
        return true;
      }
      // No stored passphrase — fall through to passphrase input
    } else if (!context.mounted) {
      return false;
    }
  }

  // Fall back to passphrase input dialog
  if (!context.mounted) return false;
  return _showPassphraseDialog(context, service, canAuth);
}

/// Attempt biometric authentication, showing a brief status indicator.
Future<bool> _attemptBiometrics(
  BuildContext context,
  BiometricAuthService service,
) async {
  final biometrics = await service.availableBiometrics();
  String reason;
  if (biometrics.contains(BiometricType.face)) {
    reason = 'Scan your face to unlock encrypted PDFs';
  } else if (biometrics.contains(BiometricType.fingerprint)) {
    reason = 'Scan your fingerprint to unlock encrypted PDFs';
  } else if (biometrics.contains(BiometricType.iris)) {
    reason = 'Scan your iris to unlock encrypted PDFs';
  } else {
    reason = 'Use your fingerprint or face to unlock encrypted PDFs';
  }

  // Brief snackbar to indicate biometric prompt is incoming
  if (context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              biometrics.contains(BiometricType.face)
                  ? Icons.face_rounded
                  : Icons.fingerprint_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            const SizedBox(width: 12),
            const Text('Biometric unlock requested…'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  final ok = await service.authenticate(reason: reason);

  if (context.mounted) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  return ok;
}

/// Full passphrase entry dialog with same visual style as the existing
/// passphrase dialog, but with a biometric retry option when available.
Future<bool> _showPassphraseDialog(
  BuildContext context,
  BiometricAuthService service,
  bool biometricsAvailable,
) async {
  final storage = BiometricPassphraseStorage();
  final controller = TextEditingController();
  bool obscure = true;
  bool showRetryBio = biometricsAvailable;

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
                  showRetryBio
                      ? Icons.fingerprint_rounded
                      : Icons.lock_rounded,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Text('Unlock PDF'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showRetryBio
                      ? 'Biometric check failed. Enter your passphrase to open this encrypted file.'
                      : 'Enter your passphrase to open this encrypted file.',
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
                    prefixIcon:
                        const Icon(Icons.vpn_key_rounded, size: 20),
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
                    if (isValid) Navigator.pop(ctx, true);
                  },
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  // Strength meter
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
                if (showRetryBio)
                  Row(
                    children: [
                      Icon(
                        Icons.fingerprint_rounded,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Biometrics available',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    '⚠️ If you forget this passphrase, encrypted PDFs cannot be recovered.',
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
              if (showRetryBio)
                TextButton.icon(
                  icon: const Icon(Icons.fingerprint_rounded, size: 18),
                  label: const Text('Try biometrics'),
                  onPressed: () async {
                    final ok = await _attemptBiometrics(ctx, service);
                    if (ok && ctx.mounted) {
                      final encryption = ctx.read<EncryptionProvider>();
                      final stored = await storage.read();
                      if (stored != null && stored.isNotEmpty) {
                        encryption.setPassphrase(stored);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                        return;
                      }
                    }
                    if (ctx.mounted) {
                      setDialogState(() => showRetryBio = false);
                    }
                  },
                ),
              FilledButton(
                onPressed: isValid
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Unlock'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true && controller.text.isNotEmpty) {
    if (context.mounted) {
      final encryption = context.read<EncryptionProvider>();
      encryption.setPassphrase(controller.text);
      // Store passphrase for future biometric unlock
      await storage.write(controller.text);
      controller.dispose();
      return true;
    }
    controller.dispose();
    return false;
  }
  controller.dispose();
  return false;
}

/// Clear the stored biometric passphrase from secure storage.
/// Call this when the user explicitly clears their session passphrase.
Future<void> clearStoredBioPassphrase() async {
  await BiometricPassphraseStorage().clear();
}
