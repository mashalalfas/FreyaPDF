// Size: medium — failure-path tests for folder scanning pipeline
//
// Verifies that the fixes for isolate error handling, cache invalidation,
// and fallback chains work end-to-end. Uses real temp directories and
// non-existent paths to simulate permission-denied / missing-dir scenarios.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/file_management/file_service.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';

/// Shared temp root for filesystem tests; cleaned up in tearDownAll.
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
    _tempRoot = Directory.systemTemp.createTempSync('freya_pdf_failure_path_');
  });

  tearDownAll(() {
    if (_tempRoot.existsSync()) {
      _tempRoot.deleteSync(recursive: true);
    }
  });

  // ── FileService failure paths ──────────────────────────────────────────

  group('FileService failure paths', () {
    // 1. scanDirectoryRecursive with non-existent directory
    // Arrange: use a path that definitely does not exist
    // Act: call scanDirectoryRecursive
    // Assert: returns empty list, does not throw
    test('scanDirectoryRecursive with non-existent directory returns empty list',
        () async {
      // Act
      final files =
          await FileService.scanDirectoryRecursive('/no/such/dir_xyz_123');

      // Assert
      expect(files, isEmpty);
    });

    // 2. scanDirectoryRecursive with empty directory
    // Arrange: create an empty temp directory
    // Act: call scanDirectoryRecursive
    // Assert: returns empty list
    test('scanDirectoryRecursive with empty directory returns empty list',
        () async {
      // Arrange
      final dir = _makeTempDir('empty_dir');

      // Act
      final files = await FileService.scanDirectoryRecursive(dir.path);

      // Assert
      expect(files, isEmpty);
    });

    // 3. scanDirectoryRecursive with PDF files (happy-path baseline)
    // Arrange: create directory with nested PDFs
    // Act: call scanDirectoryRecursive
    // Assert: all PDFs found, sorted newest first
    test('scanDirectoryRecursive with PDF files finds them (happy-path baseline)',
        () async {
      // Arrange
      final root = _makeTempDir('recursive_pdfs');
      _writePdf(root, 'root.pdf');
      final sub = _makeTempDir('recursive_pdfs/sub');
      _writePdf(sub, 'sub.pdf');

      // Act
      final files = await FileService.scanDirectoryRecursive(root.path);

      // Assert
      expect(files.length, equals(2));
      final names = files.map((f) => f.name).toList();
      expect(names, containsAll(['root.pdf', 'sub.pdf']));
    });

    // 4. isReadable with non-existent path
    // Arrange: use a path that does not exist
    // Act: call isReadable
    // Assert: returns false
    test('isReadable with non-existent path returns false', () async {
      // Act
      final result = await FileService.isReadable('/no/such/path_xyz');

      // Assert
      expect(result, isFalse);
    });

    // 5. isReadable with valid directory
    // Arrange: create a readable temp directory
    // Act: call isReadable
    // Assert: returns true
    test('isReadable with valid directory returns true', () async {
      // Arrange
      final dir = _makeTempDir('readable_dir');

      // Act
      final result = await FileService.isReadable(dir.path);

      // Assert
      expect(result, isTrue);
    });
  });

  // ── AppState failure paths ─────────────────────────────────────────────

  group('AppState failure paths', () {
    // 6. loadAllDirectories with mix of valid and invalid paths
    // Arrange: one valid dir with PDFs, one non-existent path
    // Act: call loadAllDirectories with both paths
    // Assert: files from the valid dir appear, no crash
    test('loadAllDirectories with mix of valid and invalid paths',
        () async {
      // Arrange
      final validDir = _makeTempDir('mix_valid');
      _writePdf(validDir, 'doc1.pdf');
      _writePdf(validDir, 'doc2.pdf');
      const badPath = '/no/such/dir_mix_test';

      // Act
      final state = AppState();
      await state.loadAllDirectories([badPath, validDir.path]);

      // Assert
      expect(state.files.length, equals(2));
      expect(state.error, isNull);
      expect(state.isLoading, isFalse);
      final names = state.files.map((f) => f.name).toList();
      expect(names, containsAll(['doc1.pdf', 'doc2.pdf']));
    });

    // 7. loadAllDirectories with all invalid paths
    // Arrange: only non-existent paths
    // Act: call loadAllDirectories
    // Assert: returns empty list, no crash, no error set
    test('loadAllDirectories with all invalid paths returns empty list',
        () async {
      // Act
      final state = AppState();
      await state.loadAllDirectories([
        '/no/such/dir_a',
        '/no/such/dir_b',
      ]);

      // Assert
      expect(state.files, isEmpty);
      expect(state.hasFiles, isFalse);
      expect(state.isLoading, isFalse);
      // No error — invalid paths are silently skipped
    });

    // 8. refresh clears cache so stale results are invalidated
    // Arrange: load a directory, then add a new PDF to it on disk
    // Act: call refresh()
    // Assert: the new PDF appears (proving cache was cleared and re-scanned)
    test('refresh clears cache so new files on disk are discovered', () async {
      // Arrange
      final dir = _makeTempDir('refresh_cache');
      _writePdf(dir, 'old.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);
      expect(state.files.length, equals(1));
      expect(state.files.first.name, equals('old.pdf'));

      // Add a new file to the same directory on disk (simulates external change)
      _writePdf(dir, 'new.pdf');

      // Act
      await state.refresh();

      // Assert — both files should now be present (cache was cleared)
      expect(state.files.length, equals(2));
      final names = state.files.map((f) => f.name).toList();
      expect(names, containsAll(['old.pdf', 'new.pdf']));
    });

    // Bonus: loadDirectory with empty directory — no crash, no error,
    // and empty list (contrast with the old behavior that showed "No PDFs found"
    // as a red error instead of the empty-state UI).
    test('loadDirectory with empty directory returns empty list, no error',
        () async {
      // Arrange
      final dir = _makeTempDir('empty_for_load');

      // Act
      final state = AppState();
      await state.loadDirectory(dir.path);

      // Assert
      expect(state.files, isEmpty);
      expect(state.hasFiles, isFalse);
      expect(state.error, isNull);
      expect(state.isLoading, isFalse);
    });

    // Bonus: loadDirectory with non-existent path does not crash
    test('loadDirectory with non-existent path does not crash', () async {
      // Act
      final state = AppState();
      await state.loadDirectory('/no/such/dir_load_test');

      // Assert — error is set because isReadable returns false
      expect(state.files, isEmpty);
      expect(state.hasFiles, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.error, isNotNull); // "Cannot read this directory"
    });
  });

  // ── Edge cases ─────────────────────────────────────────────────────────

  group('Edge cases', () {
    // maxDepth cap: files beyond the depth limit are excluded
    test('scanDirectoryRecursive respects maxDepth limit', () async {
      // Arrange: root(0) → l1(1) → l2(2) → l3(3) each with a PDF
      final root = _makeTempDir('depth_root');
      _writePdf(root, 'root.pdf');
      final l1 = _makeTempDir('depth_root/l1');
      _writePdf(l1, 'l1.pdf');
      final l2 = _makeTempDir('depth_root/l1/l2');
      _writePdf(l2, 'l2.pdf');
      final l3 = _makeTempDir('depth_root/l1/l2/l3');
      _writePdf(l3, 'l3.pdf');

      // Act: maxDepth=2 should exclude l3 (depth 3)
      final files =
          await FileService.scanDirectoryRecursive(root.path, maxDepth: 2);

      // Assert
      final names = files.map((f) => f.name).toList();
      expect(names, containsAll(['root.pdf', 'l1.pdf', 'l2.pdf']));
      expect(names, isNot(contains('l3.pdf')));
      expect(files.length, equals(3));
    });

    // FileService.scanDirectory on non-existent path
    test('scanDirectory with non-existent path returns empty list', () async {
      // Act
      final files = await FileService.scanDirectory('/no/such/dir_scan');

      // Assert
      expect(files, isEmpty);
    });

    // loadAllDirectories with an empty list should clear state
    test('loadAllDirectories with empty paths list clears files', () async {
      // Arrange: first load something
      final dir = _makeTempDir('clear_test');
      _writePdf(dir, 'doc.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);
      expect(state.files.length, equals(1));

      // Act: pass empty list
      await state.loadAllDirectories([]);

      // Assert
      expect(state.files, isEmpty);
      expect(state.hasFiles, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    });
  });
}
