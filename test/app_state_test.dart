// Copyright (c) 2026 Freya. All rights reserved.
// Size: medium — integration tests for AppState (ChangeNotifier + real file I/O)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';

/// Global temp root for filesystem tests; cleaned up in tearDownAll.
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
    _tempRoot = Directory.systemTemp.createTempSync('freya_pdf_app_state_');
  });

  tearDownAll(() {
    if (_tempRoot.existsSync()) {
      _tempRoot.deleteSync(recursive: true);
    }
  });

  group('AppState', () {
    // Arrange: fresh AppState, no directory loaded
    // Act: inspect initial state
    // Assert: all fields are null/empty/false
    test('starts with no directory and empty files', () {
      final state = AppState();
      expect(state.currentDir, isNull);
      expect(state.files, isEmpty);
      expect(state.hasFiles, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.selectedFile, isNull);
    });

    // Arrange: temp directory with two PDF files, fresh AppState
    // Act: call loadDirectory on the temp dir path
    // Assert: currentDir set, files list has 2 entries, hasFiles=true, isLoading=false
    test('loadDirectory populates files from a real directory', () async {
      final dir = _makeTempDir('load_basic');
      _writePdf(dir, 'doc1.pdf');
      _writePdf(dir, 'doc2.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);

      expect(state.currentDir, equals(dir.path));
      expect(state.files, hasLength(2));
      expect(state.hasFiles, isTrue);
      expect(state.isLoading, isFalse);
    });

    // Arrange: AppState with a non-existent directory path
    // Act: call loadDirectory on the bad path
    // Assert: files is empty, hasFiles is false (no crash)
    test('loadDirectory returns empty files for non-existent path', () async {
      final state = AppState();
      await state.loadDirectory('/no/such/dir_xyz_123');

      expect(state.files, isEmpty);
      expect(state.hasFiles, isFalse);
    });

    // Arrange: temp directory with a PDF and a .txt file
    // Act: call loadDirectory
    // Assert: only the PDF file appears in the files list
    test('loadDirectory ignores non-PDF files', () async {
      final dir = _makeTempDir('load_ignore');
      _writePdf(dir, 'keep.pdf');
      _writePdf(dir, 'skip.txt');

      final state = AppState();
      await state.loadDirectory(dir.path);

      expect(state.files, hasLength(1));
      expect(state.files.first.name, equals('keep.pdf'));
    });

    // Arrange: temp directory with one PDF, fresh AppState, call loadDirectory
    // Act: call selectFile on the first file in the list
    // Assert: selectedFile is set and matches the chosen file
    test('selectFile sets selectedFile to the chosen PdfFile', () async {
      final dir = _makeTempDir('select_file');
      _writePdf(dir, 'doc.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);

      final file = state.files.first;
      state.selectFile(file);

      expect(state.selectedFile, isNotNull);
      expect(state.selectedFile!.path, equals(file.path));
    });

    // Arrange: temp directory with two PDFs, fresh AppState
    // Act: select first file, then select last file
    // Assert: selectedFile path matches the last selected file
    test('selectFile with a different file changes the selection', () async {
      final dir = _makeTempDir('select_change');
      _writePdf(dir, 'a.pdf');
      _writePdf(dir, 'b.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);

      state.selectFile(state.files.first);
      expect(state.selectedFile, isNotNull);

      state.selectFile(state.files.last);
      expect(state.selectedFile!.path, equals(state.files.last.path));
    });

    // Arrange: temp directory with one PDF, fresh AppState, call loadDirectory then selectFile
    // Act: call closeFile()
    // Assert: selectedFile is null
    test('closeFile clears selectedFile to null', () async {
      final dir = _makeTempDir('close_file');
      _writePdf(dir, 'doc.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);

      state.selectFile(state.files.first);
      expect(state.selectedFile, isNotNull);

      state.closeFile();
      expect(state.selectedFile, isNull);
    });

    // Arrange: two different temp directories, each with PDFs, fresh AppState
    // Act: load first dir, then load second dir
    // Assert: files list reflects second dir, currentDir updated
    test('loading a new directory replaces the file list', () async {
      final dir1 = _makeTempDir('dir1');
      _writePdf(dir1, 'a.pdf');
      final dir2 = _makeTempDir('dir2');
      _writePdf(dir2, 'b.pdf');
      _writePdf(dir2, 'c.pdf');

      final state = AppState();
      await state.loadDirectory(dir1.path);
      expect(state.files, hasLength(1));

      await state.loadDirectory(dir2.path);
      expect(state.files, hasLength(2));
      expect(state.currentDir, equals(dir2.path));
    });

    // Arrange: temp directory with one PDF, fresh AppState, call loadDirectory
    // Act: read files getter
    // Assert: returns a List<PdfFile> (type check — internal list is immutable)
    test('files getter returns a List<PdfFile>', () async {
      final dir = _makeTempDir('modcopy');
      _writePdf(dir, 'a.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);

      // Should be able to iterate; internal _files is immutable
      expect(state.files, isA<List<PdfFile>>());
    });

    // Arrange: fresh AppState (no directory loaded), then a temp dir with a PDF
    // Act: check hasFiles before and after loadDirectory
    // Assert: false before load, true after load
    test('hasFiles is false before loading and true after loading PDFs', () async {
      final dir = _makeTempDir('hasfiles');
      final state = AppState();

      expect(state.hasFiles, isFalse);
      _writePdf(dir, 'doc.pdf');
      await state.loadDirectory(dir.path);
      expect(state.hasFiles, isTrue);
    });

    // Arrange: temp directory, fresh AppState
    // Act: call loadDirectory then read currentDir
    // Assert: currentDir equals the loaded directory path
    test('currentDir getter returns the loaded directory path', () async {
      final dir = _makeTempDir('curdir');
      final state = AppState();
      await state.loadDirectory(dir.path);
      expect(state.currentDir, equals(dir.path));
    });

    // Arrange: temp directory with a PDF, fresh AppState
    // Act: call loadDirectory
    // Assert: error is null after a successful load
    test('error is null after a successful loadDirectory', () async {
      final dir = _makeTempDir('noerr');
      _writePdf(dir, 'doc.pdf');
      final state = AppState();
      await state.loadDirectory(dir.path);
      expect(state.error, isNull);
    });

    // Arrange: temp directory with a PDF, fresh AppState
    // Act: call loadDirectory and wait for completion
    // Assert: isLoading is false after loadDirectory completes
    test('isLoading is false after loadDirectory completes', () async {
      final dir = _makeTempDir('notloading');
      _writePdf(dir, 'doc.pdf');
      final state = AppState();
      await state.loadDirectory(dir.path);
      expect(state.isLoading, isFalse);
    });

    // Arrange: temp directory with a PDF named 'report.pdf'
    // Act: loadDirectory, then inspect first file name
       // Assert: file name ends with '.pdf'
    test('file names from loadDirectory end with .pdf extension', () async {
      final dir = _makeTempDir('ext_check');
      _writePdf(dir, 'report.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);

      expect(state.files.first.name, endsWith('.pdf'));
    });

    // Arrange: temp directory with 10 PDF files, fresh AppState
    // Act: call loadDirectory
    // Assert: files list has exactly 10 entries
    test('loadDirectory returns all 10 PDF files', () async {
      final dir = _makeTempDir('multi_pdf');
      for (var i = 0; i < 10; i++) {
        _writePdf(dir, 'doc_$i.pdf');
      }

      final state = AppState();
      await state.loadDirectory(dir.path);

      expect(state.files, hasLength(10));
    });

    // Arrange: freshly constructed AppState (no loadDirectory called)
    // Act: read selectedFile
    // Assert: selectedFile is null
    test('selectedFile is null on a freshly constructed AppState', () {
      final state = AppState();
      expect(state.selectedFile, isNull);
    });

    // Arrange: temp directory with one PDF, fresh AppState
    // Act: selectFile then closeFile in sequence
    // Assert: null → not null → null
    test('selectFile then closeFile cycles selectedFile from null to null', () async {
      final dir = _makeTempDir('select_close_cycle');
      _writePdf(dir, 'doc.pdf');

      final state = AppState();
      await state.loadDirectory(dir.path);

      expect(state.selectedFile, isNull);
      state.selectFile(state.files.first);
      expect(state.selectedFile, isNotNull);
      state.closeFile();
      expect(state.selectedFile, isNull);
    });
  });
}
