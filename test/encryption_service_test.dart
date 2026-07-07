// Size: small — pure service tests (dart-only, no I/O, milliseconds)

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/features/encryption/encryption_service.dart';


void main() {
  group('EncryptionService', () {
    const passphrase = 'test-passphrase-123';

    // Arrange: a known plaintext Uint8List
    // Act: encrypt + decrypt round-trip
    // Assert: decrypted bytes equal original
    test('encrypt then decrypt returns same bytes', () {
      final original = Uint8List.fromList('Hello Feya PDF!'.codeUnits);
      final encrypted = EncryptionService.encryptBytes(original, passphrase);
      final decrypted = EncryptionService.decryptBytes(encrypted, passphrase);
      expect(decrypted, equals(original));
    });

    // Arrange: known plaintext Uint8List encrypted with passphrase
    // Act: attempt decryption with wrong passphrase
    // Assert: throws EncryptionException
    test('wrong passphrase throws EncryptionException', () {
      final encrypted = EncryptionService.encryptBytes(
        Uint8List.fromList('secret data'.codeUnits),
        passphrase,
      );
      expect(
        () => EncryptionService.decryptBytes(encrypted, 'wrong-passphrase'),
        throwsA(isA<EncryptionException>()),
      );
    });

    // Arrange: encrypted bytes, then flip bits in the middle of ciphertext
    // Act: attempt decryption of corrupted blob
    // Assert: throws EncryptionException
    test('corrupted data throws EncryptionException', () {
      // Build a "valid looking" blob by encrypting then tampering with bytes in the middle
      final encrypted = EncryptionService.encryptBytes(
        Uint8List.fromList('corruption test'.codeUnits),
        passphrase,
      );
      final corrupted = Uint8List.fromList(encrypted);
      corrupted[20] ^= 0xFF; // flip bits deep in the ciphertext
      expect(
        () => EncryptionService.decryptBytes(corrupted, passphrase),
        throwsA(isA<EncryptionException>()),
      );
    });

    // Arrange: encrypt a short payload, truncate to 10 bytes
    // Act: attempt decryption of truncated blob
    // Assert: throws EncryptionException
    test('truncated data throws EncryptionException', () {
      final encrypted = EncryptionService.encryptBytes(
        Uint8List.fromList('data'.codeUnits),
        passphrase,
      );
      final truncated = encrypted.sublist(0, 10); // way too short
      expect(
        () => EncryptionService.decryptBytes(truncated, passphrase),
        throwsA(isA<EncryptionException>()),
      );
    });

    // Arrange: empty Uint8List
    // Act: encrypt then decrypt round-trip
    // Assert: decrypted length is 0
    test('empty bytes round-trips correctly', () {
      final original = Uint8List(0);
      final encrypted = EncryptionService.encryptBytes(original, passphrase);
      final decrypted = EncryptionService.decryptBytes(encrypted, passphrase);
      expect(decrypted.length, equals(0));
    });

    // Arrange: 1 MB of pseudo-random bytes seeded with a fixed Random
    // Act: encrypt then decrypt round-trip
    // Assert: decrypted bytes equal original 1 MB payload
    test('large payload (1MB random data) round-trips correctly', () {
      final random = Random(42);
      final original = Uint8List.fromList(
        List.generate(1 * 1024 * 1024, (_) => random.nextInt(256)),
      );
      final encrypted = EncryptionService.encryptBytes(original, passphrase);
      final decrypted = EncryptionService.decryptBytes(encrypted, passphrase);
      expect(decrypted, equals(original));
    });

    // Arrange: same plaintext encrypted with two different passphrases
    // Act: compare ciphertexts
    // Assert: ciphertexts differ (random salt/IV per call)
    test('different passphrases produce different ciphertexts', () {
      final original = Uint8List.fromList('same plaintext'.codeUnits);
      final enc1 = EncryptionService.encryptBytes(original, 'pass-a');
      final enc2 = EncryptionService.encryptBytes(original, 'pass-b');
      // Ciphertexts differ (random salt/IV per call)
      expect(enc1, isNot(equals(enc2)));
    });

    // Arrange: encrypt any payload
    // Act: inspect first 4 bytes of ciphertext
    // Assert: bytes match ASCII 'FEYA' magic header (0x46 0x45 0x59 0x41)
    test('encrypted output has magic header FEYA', () {
      final encrypted = EncryptionService.encryptBytes(
        Uint8List.fromList('header check'.codeUnits),
        passphrase,
      );
      expect(encrypted[0], equals(0x46));
      expect(encrypted[1], equals(0x45));
      expect(encrypted[2], equals(0x59));
      expect(encrypted[3], equals(0x41));
    });

    // Arrange: all 256 possible byte values (not valid UTF-8 as a whole)
    // Act: encrypt then decrypt round-trip
    // Assert: decrypted bytes equal original byte sequence
    test('binary data (non-UTF8 bytes) round-trips correctly', () {
      // Bytes that are not valid UTF-8 — proves we're handling raw bytes, not strings
      final original = Uint8List.fromList(List.generate(256, (i) => i));
      final encrypted = EncryptionService.encryptBytes(original, passphrase);
      final decrypted = EncryptionService.decryptBytes(encrypted, passphrase);
      expect(decrypted, equals(original));
    });
  });
}
