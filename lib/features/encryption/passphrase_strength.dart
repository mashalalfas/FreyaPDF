import 'package:flutter/material.dart';

/// Common password patterns that are trivially guessable.
const commonPasswords = {
  'password', 'password123', '123456', '1234567', '12345678', '123456789',
  'qwerty', 'qwerty123', 'qwertyui', 'qwertyuiop',
  'admin123', 'letmein1', 'welcome1', 'monkey12', 'dragon12',
  'master12', 'abc123', 'abc12345', 'trustno1', 'sunshine', 'iloveyou',
  'princess', 'football', 'shadow12', 'michael1', 'jordan23',
  'superman', 'batman12', 'starwars', 'feyapdf1', 'melodypd',
};

enum PassphraseStrength { weak, fair, strong, veryStrong }

PassphraseStrength calculateStrength(String passphrase) {
  if (passphrase.isEmpty) return PassphraseStrength.weak;

  int score = 0;

  // Length scoring
  if (passphrase.length >= 8) score++;
  if (passphrase.length >= 12) score++;
  if (passphrase.length >= 16) score++;

  // Character variety
  if (passphrase.contains(RegExp(r'[a-z]'))) score++;
  if (passphrase.contains(RegExp(r'[A-Z]'))) score++;
  if (passphrase.contains(RegExp(r'[0-9]'))) score++;
  if (passphrase.contains(RegExp(r'[^a-zA-Z0-9]'))) score++;

  // Entropy check: penalize repeated characters
  final uniqueRatio = passphrase.runes.toSet().length / passphrase.length;
  if (uniqueRatio > 0.7) score++;

  if (score <= 3) return PassphraseStrength.weak;
  if (score <= 5) return PassphraseStrength.fair;
  if (score <= 7) return PassphraseStrength.strong;
  return PassphraseStrength.veryStrong;
}

bool isCommonPassword(String passphrase) {
  return commonPasswords.contains(passphrase.toLowerCase());
}

String strengthLabel(PassphraseStrength strength) {
  switch (strength) {
    case PassphraseStrength.weak:
      return 'Weak';
    case PassphraseStrength.fair:
      return 'Fair';
    case PassphraseStrength.strong:
      return 'Strong';
    case PassphraseStrength.veryStrong:
      return 'Very Strong';
  }
}

Color strengthColor(PassphraseStrength strength, ColorScheme cs) {
  switch (strength) {
    case PassphraseStrength.weak:
      return cs.error;
    case PassphraseStrength.fair:
      return cs.tertiary;
    case PassphraseStrength.strong:
      return cs.primary;
    case PassphraseStrength.veryStrong:
      return Colors.green.shade600;
  }
}

double strengthFill(PassphraseStrength strength) {
  switch (strength) {
    case PassphraseStrength.weak:
      return 0.25;
    case PassphraseStrength.fair:
      return 0.5;
    case PassphraseStrength.strong:
      return 0.75;
    case PassphraseStrength.veryStrong:
      return 1.0;
  }
}
