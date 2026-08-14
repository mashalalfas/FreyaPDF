// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';

/// Shows a confirmation dialog offering to delete the ORIGINAL (plaintext)
/// files after encryption has produced the `.enc` copy.
///
/// Returns `true` if the user explicitly taps **Delete** (destructive action),
/// `false` for **Keep**. The dialog is NOT barrier-dismissible, so tapping
/// outside can never trigger a delete — the user must explicitly choose one of
/// the two actions (or dismiss via the system back button, which is treated as
/// Keep because the caller only deletes on a `true` result).
Future<bool> showDeleteOriginalDialog(
  BuildContext context, {
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    // Safer-of-two-options: the dialog cannot be dismissed by tapping outside,
    // so an accidental outside tap can never result in deleting the originals.
    // Only an explicit "Delete" tap returns true; everything else is Keep.
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            Icons.lock_rounded,
            color: Theme.of(ctx).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          const Text('Delete original?'),
        ],
      ),
      content: Text(message),
      actions: [
        // Default action is "Keep" — it is the first (leftmost) button and
        // doing nothing is always the safe default.
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  // Treat any non-true outcome (Keep, or back-button dismissal) as Keep.
  return result == true;
}
