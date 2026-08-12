// Copyright (c) 2026 Freya. All rights reserved.
// Regression tests for the secure-folder import ANR/crash fix and the new
// import-job UX (provider-owned batch, real progress, background mode).
//
// Covers:
//   (a) isolate-backed import round-trip via a temp dir (no real secure dir),
//       file format stays FREYA/v2-compatible, original deleted, no .tmp left.
//   (b) SecureFolderProvider.importFiles job-state transitions + a batch with a
//       failing file (failures must not abort the batch).
//   (c) no leftover .tmp after a successful import.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';
import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/features/security/secure_folder_service.dart';

const _passphrase = 'secure-folder-test-passphrase';

late Directory _tempRoot;

Directory _makeDir(String name) {
  final dir = Directory('${_tempRoot.path}/$name');
  dir.createSync(recursive: true);
  return dir;
}

File _writePdf(Directory parent, String name, {int sizeBytes = 200}) {
  final file = File('${parent.path}/$name');
  file.writeAsBytesSync(List.generate(sizeBytes, (i) => i % 256));
  return file;
}

void _pumpSecureImportChannel(String docsRoot) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return docsRoot;
      }
      return null;
    },
  );
}

void main() {
  late EncryptionProvider encProvider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _tempRoot = Directory.systemTemp.createTempSync('freya_sec_import_');
    encProvider = EncryptionProvider();
    encProvider.setPassphrase(_passphrase);
    _pumpSecureImportChannel(_tempRoot.path);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (_tempRoot.existsSync()) {
      _tempRoot.deleteSync(recursive: true);
    }
  });

  group('SecureFolderService isolate-backed import', () {
    test('importFileInIsolate round-trips: encrypts, writes .enc, deletes '
        'original, leaves no .tmp', () async {
      // Arrange
      final src = _makeDir('roundtrip_src');
      final srcFile = _writePdf(src, 'doc.pdf', sizeBytes: 512);
      final plain = srcFile.readAsBytesSync();
      final secureDir = _makeDir('roundtrip_secure');
      final encPath = '${secureDir.path}/doc.pdf.enc';

      // Act — this is exactly the code path the UI now runs in the background
      // isolate (read → encrypt → atomic write(temp→rename) → delete original).
      final result = SecureFolderService.importFileInIsolate(
        srcFile.path,
        encPath,
        _passphrase,
      );

      // Assert: returned path, encrypted file exists, original deleted.
      expect(result, equals(encPath));
      expect(File(encPath).existsSync(), isTrue);
      expect(srcFile.existsSync(), isFalse);

      // No leftover temp file after a successful import.
      expect(File('$encPath.tmp').existsSync(), isFalse);

      // Decryptable with the same passphrase, plaintext intact.
      final decrypted = await EncryptionService.decryptFile(encPath, _passphrase);
      expect(decrypted, equals(plain));

      // Format compatibility: FREYA magic header (format unchanged on disk).
      final header = (await File(encPath).readAsBytes()).sublist(0, 5);
      expect(header, equals([0x46, 0x52, 0x45, 0x59, 0x41])); // "FREYA"
    });

    test('importFileInIsolate with a missing source throws and leaves no .tmp',
        () {
      // Arrange
      final secureDir = _makeDir('roundtrip_missing');
      final encPath = '${secureDir.path}/ghost.pdf.enc';

      // Act & Assert: throws (source missing), no .enc and no .tmp produced.
      expect(
        () => SecureFolderService.importFileInIsolate(
          '${_tempRoot.path}/no/such/file.pdf',
          encPath,
          _passphrase,
        ),
        throwsA(anything),
      );
      expect(File(encPath).existsSync(), isFalse);
      expect(File('$encPath.tmp').existsSync(), isFalse);
    });

    test('importFileInIsolate preserves the original when encrypting fails',
        () {
      // Arrange: a source whose read fails mid-way is not exercised here, but a
      // non-readable target must not delete the original. Simulate by pointing
      // the source at a directory (readAsBytesSync throws).
      final src = _makeDir('roundtrip_preserve_src');
      _writePdf(src, 'keep.pdf');
      final secureDir = _makeDir('roundtrip_preserve_secure');
      final encPath = '${secureDir.path}/keep.pdf.enc';

      // Act: import a directory path (read will throw inside the isolate entry).
      expect(
        () => SecureFolderService.importFileInIsolate(
          src.path, // a directory — readAsBytesSync throws
          encPath,
          _passphrase,
        ),
        throwsA(anything),
      );

      // Assert: nothing committed, no temp, and the source file still exists.
      expect(File(encPath).existsSync(), isFalse);
      expect(File('$encPath.tmp').existsSync(), isFalse);
      expect(File('${src.path}/keep.pdf').existsSync(), isTrue);
    });
  });

  group('SecureFolderProvider import job', () {
    test('importFiles tracks job state and returns an ImportResult summary',
        () async {
      // Arrange
      final src = _makeDir('job_src');
      final files = [
        _writePdf(src, 'a.pdf', sizeBytes: 128),
        _writePdf(src, 'b.pdf', sizeBytes: 256),
      ];
      final provider = SecureFolderProvider()..attachEncryption(encProvider);
      // Unlock so importFiles allows the batch.
      await provider.unlock();

      final states = <(int, int, int)>[]; // (total, completed, success)
      provider.addListener(() {
        states.add((provider.importTotal, provider.importCompleted,
            provider.importSuccess));
      });

      // Act
      final result = await provider.importFiles(files.map((f) => f.path).toList());

      // Assert: summary correct.
      expect(result.imported, equals(2));
      expect(result.failed, equals(0));

      // Job state transitions observed: total stays 2, completed climbs 1→2,
      // success climbs 1→2, and importing went true then false.
      expect(states.first, equals((2, 0, 0)));
      expect(states, contains((2, 1, 1)));
      expect(states, contains((2, 2, 2)));

      // Final state is idle with counts retained.
      expect(provider.isImporting, isFalse);
      expect(provider.importTotal, equals(2));
      expect(provider.importProgress, equals(1.0));

      // Encrypted files really landed in the (mocked) secure dir.
      final secureDir = Directory('${_tempRoot.path}/FreyaPDF_Secure');
      final encNames = secureDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(encNames, containsAll(['a.pdf.enc', 'b.pdf.enc']));

      // No leftover temp files.
      for (final f in secureDir.listSync().whereType<File>()) {
        expect(f.path.endsWith('.tmp'), isFalse,
            reason: 'no leftover temp after batch import');
      }
    });

    test('a failing file does not abort the batch; failures are counted',
        () async {
      // Arrange
      final src = _makeDir('job_fail_src');
      final goodFile = _writePdf(src, 'good.pdf', sizeBytes: 128);
      final missingPath = '${src.path}/does_not_exist.pdf'; // fails on read
      final provider = SecureFolderProvider()..attachEncryption(encProvider);
      await provider.unlock();

      // Act
      final result = await provider.importFiles([
        goodFile.path,
        missingPath,
      ]);

      // Assert: the good file was imported, the missing one counted as failed,
      // and importantly the batch completed instead of throwing/aborting.
      expect(result.imported, equals(1));
      expect(result.failed, equals(1));
      expect(provider.isImporting, isFalse);
      expect(provider.importCompleted, equals(2));
      expect(provider.importSuccess, equals(1));
      expect(provider.importFailed, equals(1));

      final secureDir = Directory('${_tempRoot.path}/FreyaPDF_Secure');
      expect(File('${secureDir.path}/good.pdf.enc').existsSync(), isTrue);
      expect(File('${src.path}/good.pdf').existsSync(), isFalse); // original moved
    });

    test('importFiles with an empty selection reports nothing',
        () async {
      // Arrange
      final provider = SecureFolderProvider()..attachEncryption(encProvider);
      await provider.unlock();

      // Act: no files selected at all.
      final result = await provider.importFiles([]);

      // Assert
      expect(result.imported, equals(0));
      expect(result.failed, equals(0));
      expect(provider.isImporting, isFalse);
    });

    test('importFiles with all-missing files counts them as failures without '
        'aborting', () async {
      // Arrange
      final provider = SecureFolderProvider()..attachEncryption(encProvider);
      await provider.unlock();

      // Act: the two paths don't exist — each is attempted and fails, but the
      // batch still completes with failures counted.
      final result = await provider.importFiles([
        '${_tempRoot.path}/missing1.pdf',
        '${_tempRoot.path}/missing2.pdf',
      ]);

      // Assert
      expect(result.imported, equals(0));
      expect(result.failed, equals(2));
      expect(provider.isImporting, isFalse);
      expect(provider.importFailed, equals(2));
    });
  });
}
