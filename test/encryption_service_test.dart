// Copyright (c) 2026 Freya. All rights reserved.
// Size: small — pure service tests (dart-only, no I/O, milliseconds)

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';


void main() {
  group('EncryptionService', () {
    const passphrase = 'test-passphrase-123';

    // Guard the OWASP-level KDF strength: a silent regression that lowers the
    // iteration count (weakening the derived key) must fail CI.
    test('PBKDF2 iteration count is exactly 600000', () {
      expect(EncryptionService.iterations, equals(600000),
          reason: 'the KDF iteration count must never silently drop');
    });

    // Arrange: a known plaintext Uint8List
    // Act: encrypt + decrypt round-trip
    // Assert: decrypted bytes equal original
    test('encrypt then decrypt returns same bytes', () {
      final original = Uint8List.fromList('Hello Freya PDF!'.codeUnits);
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
    test(
      'large payload (1MB random data) round-trips correctly',
      () {
        final random = Random(42);
        final original = Uint8List.fromList(
          List.generate(1 * 1024 * 1024, (_) => random.nextInt(256)),
        );
        final encrypted = EncryptionService.encryptBytes(original, passphrase);
        final decrypted = EncryptionService.decryptBytes(encrypted, passphrase);
        expect(decrypted, equals(original));
      },
      tags: {'slow'}, // excluded from CI to keep the suite fast
    );

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
    // Act: inspect first 5 bytes of ciphertext
    // Assert: bytes match ASCII 'FREYA' magic header (0x46 0x52 0x45 0x59 0x41)
    test('encrypted output has magic header FREYA', () {
      final encrypted = EncryptionService.encryptBytes(
        Uint8List.fromList('header check'.codeUnits),
        passphrase,
      );
      expect(encrypted[0], equals(0x46)); // F
      expect(encrypted[1], equals(0x52)); // R
      expect(encrypted[2], equals(0x45)); // E
      expect(encrypted[3], equals(0x59)); // Y
      expect(encrypted[4], equals(0x41)); // A
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

  group('EncryptionService file-level IO (encryptFile/decryptFile)', () {
    const passphrase = 'test-passphrase-123';
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('freya_enc_test');
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    // A real PDF-like binary payload (with a %PDF header and non-text bytes).
    Uint8List samplePdfBytes() => Uint8List.fromList([
          ...'%PDF-1.7\n'.codeUnits,
          ...List.generate(512, (i) => (i * 7) % 251),
          ...'%%EOF'.codeUnits,
        ]);

    test('encryptFile → decryptFile round-trips a real file', () async {
      final plainFile = File('${tmp.path}/sample.pdf');
      await plainFile.writeAsBytes(samplePdfBytes());

      final encPath = await EncryptionService.encryptFile(
        plainFile.path,
        passphrase,
      );
      expect(encPath, equals('${plainFile.path}.enc'));
      expect(File(encPath).existsSync(), isTrue);

      final decrypted =
          await EncryptionService.decryptFile(encPath, passphrase);
      expect(decrypted, equals(await plainFile.readAsBytes()));
    });

    test('encryptFile honours an explicit output path', () async {
      final plainFile = File('${tmp.path}/a.pdf');
      await plainFile.writeAsBytes(samplePdfBytes());
      final outPath = '${tmp.path}/custom.enc';

      final encPath =
          await EncryptionService.encryptFile(plainFile.path, passphrase,
              outputPath: outPath);
      expect(encPath, equals(outPath));
      expect(File(outPath).existsSync(), isTrue);

      final decrypted = await EncryptionService.decryptFile(outPath, passphrase);
      expect(decrypted, equals(await plainFile.readAsBytes()));
    });

    test('decryptFile rejects a wrong passphrase', () async {
      final plainFile = File('${tmp.path}/secret.pdf');
      await plainFile.writeAsBytes(samplePdfBytes());
      final encPath =
          await EncryptionService.encryptFile(plainFile.path, passphrase);

      expect(
        () => EncryptionService.decryptFile(encPath, 'wrong-passphrase'),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('decryptFile rejects a corrupted encrypted file', () async {
      final plainFile = File('${tmp.path}/c.pdf');
      await plainFile.writeAsBytes(samplePdfBytes());
      final encPath =
          await EncryptionService.encryptFile(plainFile.path, passphrase);

      // Flip a byte deep in the ciphertext, bypassing the header.
      final corrupted = await File(encPath).readAsBytes();
      corrupted[40] ^= 0xFF;
      await File(encPath).writeAsBytes(corrupted);

      expect(
        () => EncryptionService.decryptFile(encPath, passphrase),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('decryptFile rejects a file that was never encrypted', () async {
      final fakeFile = File('${tmp.path}/plain.pdf');
      await fakeFile.writeAsBytes('%PDF-1.7 not encrypted'.codeUnits);

      expect(
        () => EncryptionService.decryptFile(fakeFile.path, passphrase),
        throwsA(isA<EncryptionException>()),
      );
    });
  });
}
