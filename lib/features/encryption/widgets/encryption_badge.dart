import 'package:flutter/material.dart';

/// Small lock badge shown on encrypted file tiles.
class EncryptionBadge extends StatelessWidget {
  const EncryptionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.lock_rounded,
        size: 12,
        color: Theme.of(context).colorScheme.onTertiaryContainer,
      ),
    );
  }
}
