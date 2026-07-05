// Tests for the encrypted `.feya` backup format added to BackupService.
//
// Covers:
//  - looksEncrypted correctly identifies the magic header
//  - encryptBackupJson / decryptBackupToJson round-trips
//  - decrypt with wrong passphrase fails cleanly
//  - plain JSON backups are still accepted by looksEncrypted==false
//  - full export → encrypt → decrypt → importFromJson chain works

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feya_pdf/features/bookmarks/bookmark_service.dart';
import 'package:feya_pdf/features/encryption/encryption_service.dart';
import 'package:feya_pdf/features/highlights/highlight_service.dart';
import 'package:feya_pdf/features/settings/backup_service.dart';
import 'package:feya_pdf/features/settings/settings_service.dart';
import 'package:feya_pdf/features/tags/tag_service.dart';

void main() {
  late BackupService backupService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    backupService = BackupService(
      settingsService: SettingsService(prefs),
      tagService: TagService(prefs),
      highlightService: HighlightService(prefs),
      bookmarkService: BookmarkService(prefs),
    );
  });

  group('BackupService.looksEncrypted', () {
    test('returns false for empty bytes', () {
      expect(BackupService.looksEncrypted(Uint8List(0)), isFalse);
    });

    test('returns false for plain JSON starting with `{`', () {
      final json = utf8.encode('{"hello":"world"}');
      expect(BackupService.looksEncrypted(Uint8List.fromList(json)), isFalse);
    });

    test('returns false for JSON starting with whitespace then `{`', () {
      final json = utf8.encode('  {"hello":"world"}');
      expect(BackupService.looksEncrypted(Uint8List.fromList(json)), isFalse);
    });

    test('returns true for bytes prefixed with F-E-Y-A magic', () {
      final bytes = Uint8List.fromList(const [
        0x46, 0x45, 0x59, 0x41, // 'FEYA'
        0x4D, 0x45, 0x4C, 0x59, // 'MELY' (encryption service magic)
        0x01,
        // ... rest doesn't matter for the test
      ]);
      expect(BackupService.looksEncrypted(bytes), isTrue);
    });

    test('returns false for F-E-Y-Z (one byte off)', () {
      final bytes = Uint8List.fromList(const [
        0x46, 0x45, 0x59, 0x5A, // 'FEYZ'
      ]);
      expect(BackupService.looksEncrypted(bytes), isFalse);
    });
  });

  group('BackupService encrypt/decrypt round-trip', () {
    const passphrase = 'backup-passphrase-2026';

    test('encrypted output starts with FEYA magic', () {
      final encrypted =
          backupService.encryptBackupJson('{"hello":"world"}', passphrase);
      expect(encrypted.length, greaterThan(4));
      expect(encrypted[0], equals(0x46)); // F
      expect(encrypted[1], equals(0x45)); // E
      expect(encrypted[2], equals(0x59)); // Y
      expect(encrypted[3], equals(0x41)); // A
    });

    test('encryptBackupJson → decryptBackupToJson round-trips JSON', () {
      const original = '{"metadata":{"version":1},"data":{"tags":[]}}';
      final encrypted = backupService.encryptBackupJson(original, passphrase);
      final decrypted = backupService.decryptBackupToJson(encrypted, passphrase);
      expect(decrypted, equals(original));
    });

    test('decrypt with wrong passphrase throws EncryptionException', () {
      final encrypted = backupService.encryptBackupJson('{"a":1}', passphrase);
      expect(
        () => backupService.decryptBackupToJson(encrypted, 'not-the-passphrase'),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('decrypt throws when payload lacks FEYA magic', () {
      // Encrypt with the lower-level service so bytes start with MELY,
      // not FEYA — simulating a plain-bytes payload passed by mistake.
      final bare = EncryptionService.encryptBytes(
        Uint8List.fromList(utf8.encode('hello')),
        passphrase,
      );
      expect(
        () => backupService.decryptBackupToJson(bare, passphrase),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('two encryptions of the same JSON differ (random IV/salt)', () {
      const json = '{"a":1}';
      final a = backupService.encryptBackupJson(json, passphrase);
      final b = backupService.encryptBackupJson(json, passphrase);
      expect(a, isNot(equals(b)));
      // Both still start with FEYA magic.
      expect(a.sublist(0, 4), equals(b.sublist(0, 4)));
    });

    test('encrypted payload is longer than the raw JSON (overhead)', () {
      const json = '{"a":1}';
      final raw = Uint8List.fromList(utf8.encode(json));
      final encrypted = backupService.encryptBackupJson(json, passphrase);
      // Magic (4) + MELY header (5) + iv (12) + salt (32) + tag (16)
      // = 69 bytes of overhead minimum.
      expect(encrypted.length, greaterThan(raw.length + 60));
    });
  });

  group('BackupService encrypted end-to-end import chain', () {
    const passphrase = 'end-to-end-pass';

    test('exportAll → encrypt → decrypt → importFromJson restores', () async {
      // Build a minimal backup JSON via exportAll.
      final json = await backupService.exportAll(recentFilePaths: ['/a.pdf']);
      final encrypted = backupService.encryptBackupJson(json, passphrase);

      // Sanity: encrypted payload is detected as encrypted.
      expect(BackupService.looksEncrypted(encrypted), isTrue);

      // Decrypt round-trip brings back the same JSON content.
      final decrypted = backupService.decryptBackupToJson(encrypted, passphrase);
      expect(jsonDecode(decrypted), equals(jsonDecode(json)));

      // Importing the decrypted JSON works and reports success.
      final ok = await backupService.importFromJson(decrypted);
      expect(ok, isTrue);
    });
  });
}
