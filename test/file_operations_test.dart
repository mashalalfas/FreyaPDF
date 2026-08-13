// Copyright (c) 2026 Freya. All rights reserved.
// Size: medium — integration tests for FileOperationsProvider (ChangeNotifier + file I/O)
//
// Coverage breakdown (target 15% integration):
//   saveToLocal: 5 tests  (copy, exists, mkdir, missing src, notify)
//   deleteFile:  3 tests  (delete+notify, missing, no-notify on fail)
//   shareFile:   2 tests  (plain path, missing path — no throw)
//   encryptFile: 2 tests  (no EP attached, attached EP + notify)
//   Total:      12 tests

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';
import 'package:freya_pdf/features/file_management/file_operations_provider.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';

/// Temp root for all filesystem operations in this file.
late Directory _tempRoot;

/// Encrypt [plainPath], returning the resulting `.pdf.enc` path.
/// Convenience helper for decrypt tests.
Future<String> _encryptWith(
  FileOperationsProvider provider,
  String plainPath,
) async {
  final result = await provider.encryptFile(
    PdfFile.fromFileSystem(File(plainPath)),
  );
  expect(result, isNotNull);
  return result!;
}

Directory _makeTempDir(String name) {
  final dir = Directory('${_tempRoot.path}/$name');
  dir.createSync(recursive: true);
  return dir;
}

File _writePdf(Directory parent, String name, {int sizeBytes = 100}) {
  final file = File('${parent.path}/$name');
  file.writeAsBytesSync(List.generate(sizeBytes, (i) => i % 256));
  return file;
}

PdfFile _pdfFileAt(Directory dir, String name) => PdfFile(
      path: '${dir.path}/$name',
      name: name,
      sizeBytes: 100,
      modified: DateTime.now(),
    );

void main() {
  setUpAll(() {
    _tempRoot = Directory.systemTemp.createTempSync('freya_pdf_fops_');
  });

  tearDownAll(() {
    if (_tempRoot.existsSync()) _tempRoot.deleteSync(recursive: true);
  });

  group('FileOperationsProvider.saveToLocal', () {
    // Arrange: source PDF in temp dir, empty destination dir, fresh provider.
    // Act: call saveToLocal(sourcePath, targetDir: destDir.path).
    // Assert: SaveResult.success, destination file exists with same content.

    test('copies source file to target directory and returns success', () async {
      // Arrange
      final srcDir = _makeTempDir('save_src');
      final srcFile = _writePdf(srcDir, 'source.pdf', sizeBytes: 200);
      final destDir = _makeTempDir('save_dest');
      final provider = FileOperationsProvider();

      // Act
      final (result, destPath) = await provider.saveToLocal(
        srcFile.path,
        targetDir: destDir.path,
      );

      // Assert
      expect(result, equals(SaveResult.success));
      expect(destPath, isNotNull);
      expect(File(destPath!).existsSync(), isTrue);
      expect(File(destPath).lengthSync(), equals(200));
    });

    test('returns alreadyExists when destination file is already present', () async {
      // Arrange
      final srcDir = _makeTempDir('save_exists_src');
      final srcFile = _writePdf(srcDir, 'dup.pdf');
      final destDir = _makeTempDir('save_exists_dest');
      // Pre-create the destination so it already exists
      final preExisting = File('${destDir.path}/dup.pdf');
      preExisting.writeAsBytesSync([1, 2, 3]);
      final provider = FileOperationsProvider();

      // Act
      final (result, destPath) = await provider.saveToLocal(
        srcFile.path,
        targetDir: destDir.path,
      );

      // Assert
      expect(result, equals(SaveResult.alreadyExists));
      expect(destPath, equals(preExisting.path));
    });

    test('creates destination directory recursively when it does not exist', () async {
      // Arrange
      final srcDir = _makeTempDir('save_mkdir_src');
      final srcFile = _writePdf(srcDir, 'doc.pdf');
      final deepDest = '${_tempRoot.path}/save_mkdir/a/b/c';
      final provider = FileOperationsProvider();

      // Act
      final (result, destPath) = await provider.saveToLocal(
        srcFile.path,
        targetDir: deepDest,
      );

      // Assert
      expect(result, equals(SaveResult.success));
      expect(destPath, isNotNull);
      expect(Directory(deepDest).existsSync(), isTrue);
      expect(File(destPath!).existsSync(), isTrue);
    });

    test('returns failure when source file path does not exist', () async {
      // Arrange
      final destDir = _makeTempDir('save_fail_dest');
      final provider = FileOperationsProvider();

      // Act
      final (result, destPath) = await provider.saveToLocal(
        '/nonexistent/source.pdf',
        targetDir: destDir.path,
      );

      // Assert
      expect(result, equals(SaveResult.failure));
      expect(destPath, isNull);
    });

    test('notifies listeners after a successful save', () async {
      // Arrange
      final srcDir = _makeTempDir('save_notify_src');
      final srcFile = _writePdf(srcDir, 'notify.pdf');
      final destDir = _makeTempDir('save_notify_dest');
      final provider = FileOperationsProvider();
      var listenerCallCount = 0;
      provider.addListener(() => listenerCallCount++);

      // Act
      final (result, _) = await provider.saveToLocal(
        srcFile.path,
        targetDir: destDir.path,
      );

      // Assert
      expect(result, equals(SaveResult.success));
      expect(listenerCallCount, equals(1));
    });
  });

  group('FileOperationsProvider.deleteFile', () {
    // Arrange: real temp file, fresh provider with listener counter.
    // Act: call deleteFile(pdfFile).
    // Assert: success flag, file gone from disk, listener called (or not).

    test('returns true and notifies listeners when file is deleted', () async {
      // Arrange
      final dir = _makeTempDir('del_notify');
      final file = _writePdf(dir, 'delete_me.pdf');
      final provider = FileOperationsProvider();
      var listenerCallCount = 0;
      provider.addListener(() => listenerCallCount++);
      final pdfFile = _pdfFileAt(dir, 'delete_me.pdf');

      // Act
      final success = await provider.deleteFile(pdfFile);

      // Assert
      expect(success, isTrue);
      expect(file.existsSync(), isFalse);
      expect(listenerCallCount, equals(1));
    });

    test('returns false when file does not exist on disk', () async {
      // Arrange
      final dir = _makeTempDir('del_missing');
      final provider = FileOperationsProvider();
      final pdfFile = _pdfFileAt(dir, 'nonexistent.pdf');

      // Act
      final success = await provider.deleteFile(pdfFile);

      // Assert
      expect(success, isFalse);
    });

    test('does not notify listeners when deletion fails', () async {
      // Arrange
      final dir = _makeTempDir('del_no_notify');
      final provider = FileOperationsProvider();
      var listenerCallCount = 0;
      provider.addListener(() => listenerCallCount++);
      final pdfFile = _pdfFileAt(dir, 'ghost.pdf');

      // Act
      await provider.deleteFile(pdfFile);

      // Assert
      expect(listenerCallCount, equals(0));
    });
  });

  group('FileOperationsProvider.shareFile', () {
    // Arrange: real temp file, fresh provider.
    // Act: call shareFile(path).
    // Assert: completes without throwing (Share.shareXFiles is async no-op in test env).

    test('completes without throwing for an existing plain PDF path', () async {
      // Arrange
      final dir = _makeTempDir('share_plain');
      final file = _writePdf(dir, 'share_me.pdf');
      final provider = FileOperationsProvider();

      // Act & Assert
      await expectLater(provider.shareFile(file.path), completes);
      expect(file.existsSync(), isTrue);
    });

    test('completes without throwing for a non-existent path', () async {
      // Arrange
      final provider = FileOperationsProvider();

      // Act & Assert
      await expectLater(
        provider.shareFile('/no/such/file.pdf'),
        completes,
      );
    });
  });

  group('FileOperationsProvider.decryptFileToPlain', () {
    // Arrange: real encrypted .pdf.enc produced by encryptFile, plaintext source
    // available. Act: decryptFileToPlain on the .enc. Assert: plaintext written,
    // .enc deleted, path returned points at a valid file, no error.

    test('writes plaintext, deletes .enc, and returns the plain path', () async {
      // Arrange
      final dir = _makeTempDir('decrypt_happy');
      final originalBytes = List<int>.generate(512, (i) => i % 256);
      final plain = File('${dir.path}/secret.pdf')..writeAsBytesSync(originalBytes);
      final encProvider = EncryptionProvider()..setPassphrase('test-passphrase-123');
      final provider = FileOperationsProvider()..attachEncryption(encProvider);

      final encPath = await _encryptWith(provider, plain.path);
      expect(File(encPath).existsSync(), isTrue);
      // Drop the plaintext so decrypting produces a fresh copy.
      File(plain.path).deleteSync();
      final encPdf = _pdfFileAt(dir, 'secret.pdf.enc');

      // Act
      final result = await provider.decryptFileToPlain(encPdf);

      // Assert: plaintext restored at the original name, .enc removed, and the
      // decrypted bytes round-trip to the original plaintext.
      expect(result, plain.path);
      expect(File(result!).existsSync(), isTrue);
      expect(File(encPath).existsSync(), isFalse);
      expect(File(result).readAsBytesSync(), equals(originalBytes));
      expect(provider.lastError, isNull);
    });

    test('collision: existing target gets a suffixed name, both files valid',
        () async {
      // Arrange
      final dir = _makeTempDir('decrypt_collision');
      final original = _writePdf(dir, 'doc.pdf', sizeBytes: 300);
      final encProvider = EncryptionProvider()..setPassphrase('test-passphrase-123');
      final provider = FileOperationsProvider()..attachEncryption(encProvider);

      // Encrypt doc.pdf → doc.pdf.enc, then put a DIFFERENT file back at the
      // target name doc.pdf so decrypt hits the collision path.
      final encPath = await _encryptWith(provider, original.path);
      File(original.path).deleteSync(); // drop the plaintext
      final preExisting = File('${dir.path}/doc.pdf');
      preExisting.writeAsBytesSync(List.filled(99, 0xAB)); // different content

      final encPdf = _pdfFileAt(dir, 'doc.pdf.enc');

      // Act
      final result = await provider.decryptFileToPlain(encPdf);

      // Assert: a suffixed sibling was created, the pre-existing file untouched,
      // and the .enc removed. Both files are valid on disk.
      expect(result, '${dir.path}/doc-decrypted.pdf');
      expect(File(result!).existsSync(), isTrue);
      expect(preExisting.existsSync(), isTrue);
      expect(preExisting.lengthSync(), equals(99)); // original preserved
      expect(File(result).lengthSync(), equals(300)); // decrypted original bytes
      expect(File(encPath).existsSync(), isFalse);
      expect(provider.lastError, isNull);
    });

    test('returns null when no EncryptionProvider is attached', () async {
      // Arrange
      final dir = _makeTempDir('decrypt_no_ep');
      _writePdf(dir, 'locked.pdf');
      final provider = FileOperationsProvider();
      final pdfFile = _pdfFileAt(dir, 'locked.pdf.enc');

      // Act
      final result = await provider.decryptFileToPlain(pdfFile);

      // Assert
      expect(result, isNull);
    });
  });

  group('FileOperationsProvider.batchEncrypt progress callback', () {
    // The batch loop should invoke onProgress once per file (1-based completed),
    // advancing even for files that fail, so the UI never stalls on a skipped file.

    test('fires onProgress per file with 1-based completed counts', () async {
      // Arrange
      final dir = _makeTempDir('batch_progress');
      _writePdf(dir, 'a.pdf');
      _writePdf(dir, 'b.pdf');
      _writePdf(dir, 'c.pdf');
      final encProvider = EncryptionProvider()..setPassphrase('test-passphrase-123');
      final provider = FileOperationsProvider()..attachEncryption(encProvider);
      final reports = <(int, int)>[];

      // Act
      final encrypted = await provider.batchEncrypt(
        [
          '${dir.path}/a.pdf',
          '${dir.path}/b.pdf',
          '${dir.path}/c.pdf',
        ],
        onProgress: (completed, total) => reports.add((completed, total)),
      );

      // Assert: 3 files, callback invoked 3 times with counting totals.
      expect(encrypted.length, equals(3));
      expect(reports, hasLength(3));
      expect(reports[0], equals((1, 3)));
      expect(reports[1], equals((2, 3)));
      expect(reports[2], equals((3, 3)));
    });
  });

  group('FileOperationsProvider.encryptFile', () {
    // Arrange: plain PDF, EncryptionProvider with passphrase, attached to FileOperationsProvider.
    // Act: call encryptFile(pdfFile).
    // Assert: .pdf.enc path returned, file exists on disk, listeners notified.

    test('returns null when no EncryptionProvider is attached', () async {
      // Arrange
      final dir = _makeTempDir('enc_no_ep');
      _writePdf(dir, 'plain.pdf');
      final provider = FileOperationsProvider();
      final pdfFile = _pdfFileAt(dir, 'plain.pdf');

      // Act
      final result = await provider.encryptFile(pdfFile);

      // Assert
      expect(result, isNull);
    });

    test('encrypts file and notifies listeners when EncryptionProvider is attached',
        () async {
      // Arrange
      final dir = _makeTempDir('enc_attach');
      _writePdf(dir, 'enc_me.pdf');
      final encProvider = EncryptionProvider();
      encProvider.setPassphrase('test-passphrase-123');
      final fopsProvider = FileOperationsProvider()..attachEncryption(encProvider);
      var listenerCallCount = 0;
      fopsProvider.addListener(() => listenerCallCount++);
      final pdfFile = _pdfFileAt(dir, 'enc_me.pdf');

      // Act
      final encPath = await fopsProvider.encryptFile(pdfFile);

      // Assert
      expect(encPath, isNotNull);
      expect(File(encPath!).existsSync(), isTrue);
      expect(encPath, endsWith('.pdf.enc'));
      expect(listenerCallCount, equals(1));
      expect(fopsProvider.lastError, isNull);
    });

    // Regression: encrypting when the source file is missing must NOT throw an
    // unhandled async exception (previously a FileSystemException escaped the
    // `on EncryptionException` catch and crashed / ANR'd the app). Instead the
    // provider returns null and surfaces the error via lastError.
    test('encrypting a missing file surfaces lastError instead of crashing',
        () async {
      // Arrange
      final dir = _makeTempDir('enc_missing');
      final encProvider = EncryptionProvider();
      encProvider.setPassphrase('test-passphrase-123');
      final fopsProvider = FileOperationsProvider()..attachEncryption(encProvider);
      final pdfFile = _pdfFileAt(dir, 'ghost.pdf'); // never written to disk

      // Act
      final result = await fopsProvider.encryptFile(pdfFile);

      // Assert: no throw, null result, error surfaced.
      expect(result, isNull);
      expect(fopsProvider.lastError, isNotNull);
    });

    // Regression: re-encrypting when the .enc output already exists must
    // succeed (overwrite-safe) rather than silently fail or crash.
    test('re-encrypting an already-encrypted file overwrites successfully',
        () async {
      // Arrange
      final dir = _makeTempDir('enc_reencrypt');
      _writePdf(dir, 'doc.pdf', sizeBytes: 256);
      final encProvider = EncryptionProvider();
      encProvider.setPassphrase('test-passphrase-123');
      final fopsProvider = FileOperationsProvider()..attachEncryption(encProvider);
      final pdfFile = _pdfFileAt(dir, 'doc.pdf');

      // First encrypt
      final first = await fopsProvider.encryptFile(pdfFile);
      expect(first, isNotNull);

      // Second encrypt of the same source (output .enc already exists)
      final second = await fopsProvider.encryptFile(pdfFile);

      // Assert
      expect(second, equals(first));
      expect(File(first!).existsSync(), isTrue);
      expect(fopsProvider.lastError, isNull);
    });
  });

  group('EncryptionProvider.reEncryptFile', () {
    // Regression: re-encrypting over an existing target must succeed,
    // overwrite the old ciphertext, and leave no stale .tmp behind (mirrors
    // the atomic-write pattern from EncryptionService.encryptFile).
    test('overwrites an existing target with no leftover temp file', () async {
      // Arrange
      final dir = _makeTempDir('reenc_overwrite');
      final encPath = '${dir.path}/doc.pdf.enc';
      final provider = EncryptionProvider()..setPassphrase('test-passphrase-123');

      // Pre-encrypt once, then re-encrypt with new plaintext.
      final firstPlain = Uint8List.fromList(List.filled(256, 0x11));
      await provider.reEncryptFile(encPath, firstPlain);
      final firstEnc = await File(encPath).readAsBytes();

      final newPlain = Uint8List.fromList(List.filled(512, 0x33));

      // Act: re-encrypt over the existing target.
      await provider.reEncryptFile(encPath, newPlain);

      // Assert: target updated (different ciphertext), decrypts to newPlain,
      // no leftover temp file.
      final secondEnc = await File(encPath).readAsBytes();
      expect(secondEnc, isNot(equals(firstEnc)));
      expect(File('$encPath.tmp').existsSync(), isFalse);
      final decrypted = await EncryptionService.decryptFile(encPath, 'test-passphrase-123');
      expect(decrypted, equals(newPlain));
    });
  });
}
