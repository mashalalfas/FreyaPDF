// Size: medium — integration tests for FileOperationsProvider (ChangeNotifier + file I/O)
//
// Coverage breakdown (target 15% integration):
//   saveToLocal: 5 tests  (copy, exists, mkdir, missing src, notify)
//   deleteFile:  3 tests  (delete+notify, missing, no-notify on fail)
//   shareFile:   2 tests  (plain path, missing path — no throw)
//   encryptFile: 2 tests  (no EP attached, attached EP + notify)
//   Total:      12 tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/core/models/pdf_file.dart';
import 'package:feya_pdf/features/file_management/file_operations_provider.dart';
import 'package:feya_pdf/features/encryption/encryption_provider.dart';

/// Temp root for all filesystem operations in this file.
late Directory _tempRoot;

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
    _tempRoot = Directory.systemTemp.createTempSync('feya_pdf_fops_');
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
    });
  });
}
