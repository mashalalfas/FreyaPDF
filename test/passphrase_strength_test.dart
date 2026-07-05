// Size: small — passphrase strength evaluation tests (pure logic, no I/O)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/features/encryption/passphrase_strength.dart';

void main() {
  group('PassphraseStrength — calculateStrength', () {
    // ── Empty / very short inputs ──
    test('empty string returns weak', () {
      expect(calculateStrength(''), equals(PassphraseStrength.weak));
    });

    test('single character returns weak', () {
      expect(calculateStrength('a'), equals(PassphraseStrength.weak));
    });

    test('"abc" (3 lowercase, no variety) returns weak', () {
      expect(calculateStrength('abc'), equals(PassphraseStrength.weak));
    });

    test('"abcdefg" (7 lowercase, no variety) returns weak', () {
      expect(calculateStrength('abcdefg'), equals(PassphraseStrength.weak));
    });

    // ── Exactly 8 chars — minimum boundary ──
    test('"abcdefgh" (8 lowercase, low variety) returns weak', () {
      // score: length>=8 (+1) + lowercase (+1) = 2 → weak (≤3)
      expect(calculateStrength('abcdefgh'), equals(PassphraseStrength.weak));
    });

    test('"abcDEF12" (8 mixed case + digits) returns fair', () {
      // length>=8 (+1), lowercase (+1), uppercase (+1), digits (+1) = 4 → fair
      expect(calculateStrength('abcDEF12'), equals(PassphraseStrength.fair));
    });

    // ── Weak boundary tests ──
    test('8-char lowercase only ("abcdefgh") is weak', () {
      expect(calculateStrength('abcdefgh'), equals(PassphraseStrength.weak));
    });

    test('8-char uppercase only ("ABCDEFGH") is weak', () {
      // length>=8 (+1), uppercase (+1) = 2 → weak
      expect(calculateStrength('ABCDEFGH'), equals(PassphraseStrength.weak));
    });

    test('8-char digits only ("12345678") is weak', () {
      // length>=8 (+1), digits (+1) = 2 → weak
      expect(calculateStrength('12345678'), equals(PassphraseStrength.weak));
    });

    // ── Fair boundary tests ──
    test('"Password1" (mixed case + digit, 10 chars) returns fair', () {
      // length>=8 (+1), lowercase (+1), uppercase (+1), digits (+1) = 4 → fair
      expect(calculateStrength('Password1'), equals(PassphraseStrength.fair));
    });

    test('"helloTHERE12" (mixed case + digits, 12 chars, high uniqueness) returns strong', () {
      // length>=8 (+1), length>=12 (+1), lower (+1), upper (+1), digit (+1)
      // unique ratio: 10/12=0.833 > 0.7 (+1) → score 6 → strong
      expect(calculateStrength('helloTHERE12'), equals(PassphraseStrength.strong));
    });

    // ── Strong boundary tests ──
    test('"HelloThere123!" (mixed case + digits + special, 14 chars) returns strong', () {
      // length>=8 (+1), length>=12 (+1), lower (+1), upper (+1), digit (+1),
      // special (+1), uniqueRatio? maybe not
      // At minimum: 6+ score → strong
      expect(calculateStrength('HelloThere123!'), equals(PassphraseStrength.strong));
    });

    test('"MyP@ssword99" (mixed case + digits + special, 12 chars) returns strong', () {
      // length>=8 (+1), length>=12 (+1), lower (+1), upper (+1), digit (+1),
      // special (+1) = 6 → strong
      expect(calculateStrength('MyP@ssword99'), equals(PassphraseStrength.strong));
    });

    // ── Very Strong tests ──
    test('"P@ssw0rd!2Strong" (long, mixed, special) returns veryStrong', () {
      // 16 chars: length 8/12/16 (+3), lower (+1), upper (+1), digit (+1),
      // special (+1), high unique ratio (+1) = 8 → veryStrong
      expect(calculateStrength('P@ssw0rd!2Strong'), equals(PassphraseStrength.veryStrong));
    });

    test('"C0mpl3x!P@ssphr@s3#2024" (23 chars, diverse but some repeats) returns strong', () {
      // length 8/12/16 (+3), lower (+1), upper (+1), digit (+1), special (+1)
      // unique ratio: 15/23 = 0.652 (below 0.7 threshold due to repeats like 'ss', '@', '3')
      // total = 7 → strong (≤7)
      expect(
        calculateStrength('C0mpl3x!P@ssphr@s3#2024'),
        equals(PassphraseStrength.strong),
      );
    });

    // ── Special characters effect ──
    test('adding a special character bumps score', () {
      // "HelloThere1" (11 chars): length>=8 (+1), lower (+1), upper (+1), digit (+1) = 4 → fair
      // "HelloThere1!" (12 chars): length>=8 (+1), length>=12 (+1), lower (+1), upper (+1),
      //   digit (+1), special (+1) = 6 → strong
      expect(calculateStrength('HelloThere1'), equals(PassphraseStrength.fair));
      expect(calculateStrength('HelloThere1!'), equals(PassphraseStrength.strong));
    });

    // ── Repeated characters penalty ──
    test('repeated characters reduce score via unique ratio check', () {
      // "aaaaaaaaaa" (10 chars): length>=8 (+1), lowercase (+1) = 2 → no bonus
      // unique ratio = 1/10 = 0.1 → no bonus → weak (2 ≤ 3)
      expect(calculateStrength('aaaaaaaaaa'), equals(PassphraseStrength.weak));
    });

    test('"aaaaBBBB1111????" has variety but low uniqueness', () {
      // 16 chars: length 8/12/16 (+3), lower (+1), upper (+1), digit (+1), special (+1)
      // unique ratio = 8/16 = 0.5 → no bonus → total 7 → strong
      expect(calculateStrength('aaaaBBBB1111????'), equals(PassphraseStrength.strong));
    });
  });

  group('PassphraseStrength — strengthLabel', () {
    test('weak → "Weak"', () {
      expect(strengthLabel(PassphraseStrength.weak), equals('Weak'));
    });
    test('fair → "Fair"', () {
      expect(strengthLabel(PassphraseStrength.fair), equals('Fair'));
    });
    test('strong → "Strong"', () {
      expect(strengthLabel(PassphraseStrength.strong), equals('Strong'));
    });
    test('veryStrong → "Very Strong"', () {
      expect(strengthLabel(PassphraseStrength.veryStrong), equals('Very Strong'));
    });
  });

  group('PassphraseStrength — strengthFill', () {
    test('weak → 0.25', () {
      expect(strengthFill(PassphraseStrength.weak), equals(0.25));
    });
    test('fair → 0.5', () {
      expect(strengthFill(PassphraseStrength.fair), equals(0.5));
    });
    test('strong → 0.75', () {
      expect(strengthFill(PassphraseStrength.strong), equals(0.75));
    });
    test('veryStrong → 1.0', () {
      expect(strengthFill(PassphraseStrength.veryStrong), equals(1.0));
    });
  });

  group('PassphraseStrength — strengthColor', () {
    final cs = ColorScheme.fromSeed(seedColor: Colors.blue);

    test('weak → ColorScheme.error', () {
      expect(strengthColor(PassphraseStrength.weak, cs), equals(cs.error));
    });
    test('fair → ColorScheme.tertiary', () {
      expect(strengthColor(PassphraseStrength.fair, cs), equals(cs.tertiary));
    });
    test('strong → ColorScheme.primary', () {
      expect(strengthColor(PassphraseStrength.strong, cs), equals(cs.primary));
    });
    test('veryStrong → green shade 600', () {
      expect(
        strengthColor(PassphraseStrength.veryStrong, cs),
        equals(Colors.green.shade600),
      );
    });
  });

  group('PassphraseStrength — common password blacklist', () {
    test('isCommonPassword("password") returns true', () {
      expect(isCommonPassword('password'), isTrue);
    });

    test('isCommonPassword("Password") returns true (case-insensitive)', () {
      expect(isCommonPassword('Password'), isTrue);
    });

    test('isCommonPassword("12345678") returns true', () {
      expect(isCommonPassword('12345678'), isTrue);
    });

    test('isCommonPassword("password123") returns true', () {
      expect(isCommonPassword('password123'), isTrue);
    });

    test('isCommonPassword("sunshine") returns true', () {
      expect(isCommonPassword('sunshine'), isTrue);
    });

    test('isCommonPassword("iloveyou") returns true', () {
      expect(isCommonPassword('iloveyou'), isTrue);
    });

    test('isCommonPassword("feyapdf1") returns true', () {
      expect(isCommonPassword('feyapdf1'), isTrue);
    });

    test('isCommonPassword("MyUniqueP@ss!42") returns false', () {
      expect(isCommonPassword('MyUniqueP@ss!42'), isFalse);
    });

    test('isCommonPassword("") returns false', () {
      expect(isCommonPassword(''), isFalse);
    });
  });

  group('PassphraseStrength — 8-char minimum validation', () {
    test('"short" (< 8 chars) returns weak', () {
      expect(calculateStrength('short'), equals(PassphraseStrength.weak));
    });

    test('"1234567" (7 chars, digits) returns weak', () {
      expect(calculateStrength('1234567'), equals(PassphraseStrength.weak));
    });

    test('8-character password is NOT automatically valid if common', () {
      expect(isCommonPassword('password'), isTrue);
      // If this were used in the dialog: text.length >= 8 && isCommon → isCommon = true
      // isValid = text.length >= 8 && !isCommon → false
      // So "password" would NOT be valid despite 8 chars
    });
  });

  group('PassphraseStrength — edge cases', () {
    test('very long diverse password returns veryStrong', () {
      // Mix all character types with high uniqueness
      const longRandom = 'Xy9#mK2!wQ8%aB4^nZ7*Jc1@Df5&Lp3';
      // length >= 8/12/16 (+3), lower (+1), upper (+1), digit (+1),
      // special (+1), unique ratio > 0.7 (+1) = 8 → veryStrong
      expect(calculateStrength(longRandom), equals(PassphraseStrength.veryStrong));
    });

    test('unicode characters count toward variety', () {
      // "Passwörd123!" — includes non-ASCII that matches [^a-zA-Z0-9] = special
      expect(calculateStrength('Passwörd123!'), equals(PassphraseStrength.strong));
    });

    test('whitespace-only returns weak', () {
      expect(calculateStrength('        '), equals(PassphraseStrength.weak));
      // length>=8 (+1), special chars [^a-zA-Z0-9] (+1) = 2 → weak
    });

    test('exactly 8 special chars returns weak', () {
      expect(calculateStrength('!@#\$%^&*'), equals(PassphraseStrength.weak));
      // length>=8 (+1), special (+1) = 2 → weak
    });
  });
}
