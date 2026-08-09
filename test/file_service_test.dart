// Size: medium — integration tests for FileService (file system I/O, seconds)
//
// Tests use real temp directories; setUpAll/tearDownAll manage cleanup.
// All tests follow Arrange / Act / Assert (AAA).

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/file_management/file_service.dart';

/// Shared temp root for filesystem tests; cleaned up in tearDownAll.
late Directory _tempRoot;

Directory _makeTempDir(String name) {
  final dir = Directory('${_tempRoot.path}/$name');
  dir.createSync(recursive: true);
  return dir;
}

/// Helper: write a file with [name] and [content] under [parent].
File _writeFile(Directory parent, String name, List<int> content) {
  final file = File('${parent.path}/$name');
  file.writeAsBytesSync(content);
  return file;
}

void main() {
  setUpAll(() {
    _tempRoot = Directory.systemTemp.createTempSync('freya_pdf_fs_test_');
  });

  tearDownAll(() {
    if (_tempRoot.existsSync()) {
      _tempRoot.deleteSync(recursive: true);
    }
  });

  group('FileService.scanDirectory', () {
    // Arrange: temp directory with .pdf, .txt, .jpg, and .pdf.enc files
    // Act: call scanDirectory(dir.path)
    // Assert: only .pdf and .pdf.enc files appear, others excluded, count correct

    test('finds .pdf and .pdf.enc files and ignores non-PDF files', () async {
      // Arrange
      final dir = _makeTempDir('scan_basic');
      _writeFile(dir, 'a.pdf', [1, 2, 3]);
      _writeFile(dir, 'b.pdf', [4, 5, 6]);
      _writeFile(dir, 'c.txt', [7, 8, 9]);
      _writeFile(dir, 'd.jpg', [10, 11, 12]);
      _writeFile(dir, 'e.pdf.enc', [13, 14, 15]);

      // Act
      final files = await FileService.scanDirectory(dir.path);
      final names = files.map((f) => f.name).toList();

      // Assert
      expect(names, contains('a.pdf'));
      expect(names, contains('b.pdf'));
      expect(names, contains('e.pdf.enc'));
      expect(names, isNot(contains('c.txt')));
      expect(names, isNot(contains('d.jpg')));
      expect(files.length, equals(3));
    });

    // Arrange: call scanDirectory on a path that does not exist
    // Act: await scanDirectory
    // Assert: returns empty list, no exception thrown
    test('returns empty list for a non-existent directory', () async {
      // Act
      final files = await FileService.scanDirectory('/nonexistent/path/xyz');

      // Assert
      expect(files, isEmpty);
    });

    // Arrange: empty temp directory
    // Act: call scanDirectory
    // Assert: returns empty list
    test('returns empty list for an empty directory', () async {
      // Arrange
      final dir = _makeTempDir('empty_dir');

      // Act
      final files = await FileService.scanDirectory(dir.path);

      // Assert
      expect(files, isEmpty);
    });

    // Arrange: write 'old.pdf', wait >1s, write 'new.pdf' (newer mtime)
    // Act: scanDirectory
    // Assert: first result is 'new.pdf' (sorted newest first)
    test('results are sorted by modified time with newest first', () async {
      // Arrange
      final dir = _makeTempDir('sort_test');
      _writeFile(dir, 'old.pdf', [1]);
      await Future.delayed(const Duration(milliseconds: 1100));
      _writeFile(dir, 'new.pdf', [2]);

      // Act
      final files = await FileService.scanDirectory(dir.path);

      // Assert
      expect(files.length, equals(2));
      expect(files.first.name, equals('new.pdf'));
    });
  });

  group('FileService.scanDirectoryRecursive', () {
    // Arrange: nested directory tree with PDFs at multiple levels
    // Act: scanDirectoryRecursive
    // Assert: all PDFs found regardless of nesting depth

    test('finds PDFs in nested subdirectories', () async {
      // Arrange
      final root = _makeTempDir('recursive_root');
      _writeFile(root, 'root.pdf', [1]);
      final sub1 = _makeTempDir('recursive_root/sub1');
      _writeFile(sub1, 'sub1.pdf', [2]);
      final sub2 = _makeTempDir('recursive_root/sub1/sub2');
      _writeFile(sub2, 'sub2.pdf', [3]);

      // Act
      final files = await FileService.scanDirectoryRecursive(root.path);
      final names = files.map((f) => f.name).toList();

      // Assert
      expect(names, containsAll(['root.pdf', 'sub1.pdf', 'sub2.pdf']));
      expect(files.length, equals(3));
    });

    // Arrange: non-existent root path
    // Act: scanDirectoryRecursive
    // Assert: empty list, no exception
    test('returns empty list for a non-existent directory', () async {
      // Act
      final files = await FileService.scanDirectoryRecursive('/no/such/dir');

      // Assert
      expect(files, isEmpty);
    });

    // Arrange: root with PDF, subdirectory with .txt
    // Act: scanDirectoryRecursive
    // Assert: only the root PDF appears
    test('ignores non-PDF files in subdirectories', () async {
      // Arrange
      final root = _makeTempDir('recursive_ignore');
      _writeFile(root, 'keep.pdf', [1]);
      _makeTempDir('recursive_ignore/empty_sub');
      final sub = _makeTempDir('recursive_ignore/sub_with_txt');
      _writeFile(sub, 'skip.txt', [2]);

      // Act
      final files = await FileService.scanDirectoryRecursive(root.path);

      // Assert
      expect(files.length, equals(1));
      expect(files.first.name, equals('keep.pdf'));
    });
  });

  group('FileService.deleteFile', () {
    // Arrange: existing temp PDF file
    // Act: call deleteFile(path)
    // Assert: returns true, file no longer exists on disk
    test('deletes an existing file and returns true', () async {
      // Arrange
      final dir = _makeTempDir('del_test');
      final file = _writeFile(dir, 'delete_me.pdf', [1, 2, 3]);
      expect(file.existsSync(), isTrue);

      // Act
      final result = await FileService.deleteFile(file.path);

      // Assert
      expect(result, isTrue);
      expect(file.existsSync(), isFalse);
    });

    // Arrange: path to a file that does not exist
    // Act: call deleteFile
    // Assert: returns false
    test('returns false when the file does not exist', () async {
      // Arrange
      final dir = _makeTempDir('del_missing');
      final path = '${dir.path}/missing.pdf';

      // Act
      final result = await FileService.deleteFile(path);

      // Assert
      expect(result, isFalse);
    });
  });

  group('FileService.isReadable', () {
    // Arrange: existing temp directory
    // Act: isReadable(dir.path)
    // Assert: true
    test('returns true for an existing readable directory', () async {
      // Arrange
      final dir = _makeTempDir('readable');

      // Act
      final result = await FileService.isReadable(dir.path);

      // Assert
      expect(result, isTrue);
    });

    // Arrange: path that does not exist
    // Act: isReadable
    // Assert: false
    test('returns false for a non-existent path', () async {
      // Act
      final result = await FileService.isReadable('/no/such/path_xyz');

      // Assert
      expect(result, isFalse);
    });
  });

  group('FileService.readFileBytes', () {
    // Arrange: temp PDF file with known byte content
    // Act: readFileBytes(file.path)
    // Assert: returned list equals the original content byte-for-byte
    test('returns correct bytes for an existing file', () async {
      // Arrange
      final dir = _makeTempDir('read_bytes');
      final content = [10, 20, 30, 40, 50];
      final file = _writeFile(dir, 'data.pdf', content);

      // Act
      final bytes = await FileService.readFileBytes(file.path);

      // Assert
      expect(bytes, equals(content));
    });
  });
}
