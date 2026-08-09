// Copyright (c) 2026 Freya. All rights reserved.
// Size: medium — tests for SelectionProvider and batch operations
//
// Coverage:
//   SelectionProvider:  5 tests  (enter/exit, toggle, selectAll, clearSelection, auto-exit)
//   batchDelete:        3 tests  (counts, partial failure, no-op)
//   batchEncrypt:       2 tests  (no EP, attached EP)
//   Total:             10 tests

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/file_management/selection_provider.dart';
import 'package:freya_pdf/features/file_management/file_operations_provider.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';

/// Temp root for batch filesystem tests.
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

void main() {
  setUpAll(() {
    _tempRoot = Directory.systemTemp.createTempSync('freya_pdf_batch_');
  });

  tearDownAll(() {
    if (_tempRoot.existsSync()) _tempRoot.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // SelectionProvider
  // ---------------------------------------------------------------------------

  group('SelectionProvider', () {
    // Arrange: fresh provider, listener counter.
    // Act: enter selection mode.
    // Assert: isSelectionMode true, selectedCount 0.

    test('enterSelectionMode sets isSelectionMode true', () {
      final provider = SelectionProvider();
      var notifCount = 0;
      provider.addListener(() => notifCount++);

      provider.enterSelectionMode();

      expect(provider.isSelectionMode, isTrue);
      expect(provider.selectedCount, equals(0));
      expect(notifCount, equals(1));
    });

    // Arrange: provider in selection mode with one file selected.
    // Act: call exitSelectionMode().
    // Assert: isSelectionMode false, selectedPaths empty, listeners notified.

    test('exitSelectionMode clears selection and exits mode', () {
      final provider = SelectionProvider();
      provider.enterSelectionMode();
      provider.toggleSelection('/path/a.pdf');
      var notifCount = 0;
      provider.addListener(() => notifCount++);

      provider.exitSelectionMode();

      expect(provider.isSelectionMode, isFalse);
      expect(provider.selectedPaths, isEmpty);
      expect(notifCount, equals(1));
    });

    // Arrange: fresh provider.
    // Act: toggleSelection on one file.
    // Assert: auto-enters selection mode, file selected, notify.

    test('toggleSelection auto-enters selection mode on first select', () {
      final provider = SelectionProvider();

      provider.toggleSelection('/path/first.pdf');

      expect(provider.isSelectionMode, isTrue);
      expect(provider.selectedPaths, contains('/path/first.pdf'));
      expect(provider.selectedCount, equals(1));
    });

    // Arrange: provider in selection mode with two files selected.
    // Act: toggleSelection on one (deselect), then toggle the last (deselect).
    // Assert: auto-exits when last item deselected.

    test('toggleSelection auto-exits selection mode when last is deselected', () {
      final provider = SelectionProvider();
      provider.toggleSelection('/path/a.pdf');
      provider.toggleSelection('/path/b.pdf');
      expect(provider.selectedCount, equals(2));
      expect(provider.isSelectionMode, isTrue);

      provider.toggleSelection('/path/a.pdf');
      expect(provider.selectedCount, equals(1));
      expect(provider.isSelectionMode, isTrue);

      provider.toggleSelection('/path/b.pdf');
      expect(provider.selectedCount, equals(0));
      expect(provider.isSelectionMode, isFalse);
    });

    // Arrange: fresh provider.
    // Act: selectAll(['a', 'b', 'c']).
    // Assert: all selected, selection mode active.
    // Act: clearSelection().
    // Assert: nothing selected, mode stays active (clearSelection doesn't exit).

    test('selectAll and clearSelection work together', () {
      final provider = SelectionProvider();
      final paths = ['/p/a.pdf', '/p/b.pdf', '/p/c.pdf'];

      provider.selectAll(paths);

      expect(provider.isSelectionMode, isTrue);
      expect(provider.selectedCount, equals(3));
      expect(provider.isSelected('/p/a.pdf'), isTrue);
      expect(provider.isSelected('/p/b.pdf'), isTrue);
      expect(provider.isSelected('/p/c.pdf'), isTrue);

      provider.clearSelection();

      expect(provider.selectedCount, equals(0));
      // clearSelection does NOT auto-exit
      expect(provider.isSelectionMode, isTrue);
    });

    test('isSelected returns false for unselected paths', () {
      final provider = SelectionProvider();
      provider.toggleSelection('/path/selected.pdf');

      expect(provider.isSelected('/path/selected.pdf'), isTrue);
      expect(provider.isSelected('/path/not_selected.pdf'), isFalse);
    });

    test('selectedPaths returns an unmodifiable set', () {
      final provider = SelectionProvider();
      provider.toggleSelection('/path/a.pdf');

      final returnedSet = provider.selectedPaths;

      // Should not be the same instance as the internal set
      expect(() => returnedSet.add('/path/b.pdf'), throwsUnsupportedError);
    });
  });

  // ---------------------------------------------------------------------------
  // FileOperationsProvider.batchDelete
  // ---------------------------------------------------------------------------

  group('FileOperationsProvider.batchDelete', () {
    // Arrange: temp dir with 3 PDFs, fresh provider.
    // Act: call batchDelete with all 3 paths.
    // Assert: returns 3, all files gone from disk.

    test('returns count of successfully deleted files', () async {
      final dir = _makeTempDir('batch_del_success');
      _writePdf(dir, 'a.pdf');
      _writePdf(dir, 'b.pdf');
      _writePdf(dir, 'c.pdf');
      final paths = [
        '${dir.path}/a.pdf',
        '${dir.path}/b.pdf',
        '${dir.path}/c.pdf',
      ];
      final provider = FileOperationsProvider();

      final count = await provider.batchDelete(paths);

      expect(count, equals(3));
      expect(File(paths[0]).existsSync(), isFalse);
      expect(File(paths[1]).existsSync(), isFalse);
      expect(File(paths[2]).existsSync(), isFalse);
    });

    // Arrange: temp dir with 2 PDFs + one non-existent path.
    // Act: call batchDelete with all 3.
    // Assert: count = 2 (only existing files deleted).

    test('counts only successfully deleted files on partial failure', () async {
      final dir = _makeTempDir('batch_del_partial');
      _writePdf(dir, 'existing.pdf');
      final paths = [
        '${dir.path}/existing.pdf',
        '${dir.path}/nonexistent.pdf',
      ];
      final provider = FileOperationsProvider();

      final count = await provider.batchDelete(paths);

      expect(count, equals(1));
      expect(File(paths[0]).existsSync(), isFalse);
    });

    // Arrange: empty path list.
    // Act: call batchDelete([]).
    // Assert: returns 0, no listener notification.

    test('returns 0 for empty path list and does not notify', () async {
      final provider = FileOperationsProvider();
      var notifCallCount = 0;
      provider.addListener(() => notifCallCount++);

      final count = await provider.batchDelete([]);

      expect(count, equals(0));
      expect(notifCallCount, equals(0));
    });

    // Arrange: temp dir with file, fresh provider + listener.
    // Act: call batchDelete.
    // Assert: listener is notified (since count > 0).

    test('notifies listeners when files are deleted', () async {
      final dir = _makeTempDir('batch_del_notify');
      _writePdf(dir, 'notify.pdf');
      final provider = FileOperationsProvider();
      var notifCount = 0;
      provider.addListener(() => notifCount++);

      await provider.batchDelete(['${dir.path}/notify.pdf']);

      expect(notifCount, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // FileOperationsProvider.batchEncrypt
  // ---------------------------------------------------------------------------

  group('FileOperationsProvider.batchEncrypt', () {
    // Arrange: temp dir with 2 PDFs, no EncryptionProvider attached.
    // Act: call batchEncrypt.
    // Assert: returns empty list.

    test('returns empty list when no EncryptionProvider is attached', () async {
      final dir = _makeTempDir('batch_enc_no_ep');
      _writePdf(dir, 'a.pdf');
      _writePdf(dir, 'b.pdf');
      final paths = [
        '${dir.path}/a.pdf',
        '${dir.path}/b.pdf',
      ];
      final provider = FileOperationsProvider();

      final encrypted = await provider.batchEncrypt(paths);

      expect(encrypted, isEmpty);
    });

    // Arrange: temp dir with 2 PDFs, EncryptionProvider with passphrase attached.
    // Act: call batchEncrypt.
    // Assert: returns 2 .pdf.enc paths, files exist on disk, listeners notified.

    test('encrypts files and returns paths when EncryptionProvider is attached',
        () async {
      final dir = _makeTempDir('batch_enc_attached');
      _writePdf(dir, 'enc_a.pdf');
      _writePdf(dir, 'enc_b.pdf');
      final paths = [
        '${dir.path}/enc_a.pdf',
        '${dir.path}/enc_b.pdf',
      ];
      final encProvider = EncryptionProvider();
      encProvider.setPassphrase('test-passphrase-456');
      final fops = FileOperationsProvider()..attachEncryption(encProvider);
      var notifCount = 0;
      fops.addListener(() => notifCount++);

      final encrypted = await fops.batchEncrypt(paths);

      expect(encrypted, hasLength(2));
      for (final encPath in encrypted) {
        expect(encPath, endsWith('.pdf.enc'));
        expect(File(encPath).existsSync(), isTrue);
      }
      expect(notifCount, equals(1));
    });

    // Arrange: temp dir with one encrypted + one non-existent path.
    // Act: call batchEncrypt with both.
    // Assert: only the existing file is encrypted.

    test('skips non-existent files without error', () async {
      final dir = _makeTempDir('batch_enc_partial');
      _writePdf(dir, 'real.pdf');
      final paths = [
        '${dir.path}/real.pdf',
        '${dir.path}/ghost.pdf',
      ];
      final encProvider = EncryptionProvider();
      encProvider.setPassphrase('test-passphrase-789');
      final fops = FileOperationsProvider()..attachEncryption(encProvider);

      final encrypted = await fops.batchEncrypt(paths);

      expect(encrypted, hasLength(1));
      expect(encrypted[0], endsWith('.pdf.enc'));
    });
  });
}
