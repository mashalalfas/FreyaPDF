// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/bookmarks/bookmark.dart';
import 'package:freya_pdf/features/highlights/highlight.dart';
import 'package:freya_pdf/features/tags/tag.dart';
import 'package:freya_pdf/features/settings/backup_service.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_service.dart';
import 'package:freya_pdf/features/highlights/highlight_service.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';
import 'package:freya_pdf/features/tags/tag_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BackupService', () {
    late SharedPreferences prefs;
    late TagService tagService;
    late HighlightService highlightService;
    late BookmarkService bookmarkService;
    late SettingsService settingsService;
    late BackupService backupService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tagService = TagService(prefs);
      highlightService = HighlightService(prefs);
      bookmarkService = BookmarkService(prefs);
      settingsService = SettingsService(prefs);
      backupService = BackupService(
        settingsService: settingsService,
        tagService: tagService,
        highlightService: highlightService,
        bookmarkService: bookmarkService,
      );
    });

    // ---------------------------------------------------------------
    // Export tests
    // ---------------------------------------------------------------

    test('exportAll produces valid JSON with metadata', () async {
      final json = await backupService.exportAll(recentFilePaths: []);
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded, contains('metadata'));
      final metadata = decoded['metadata'] as Map<String, dynamic>;
      expect(metadata['version'], equals(1));
      expect(metadata['exportedAt'], isA<String>());
      expect(decoded, contains('data'));
    });

    test('exportAll includes all expected data sections', () async {
      final json = await backupService.exportAll(recentFilePaths: []);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final data = decoded['data'] as Map<String, dynamic>;

      expect(data, contains('tags'));
      expect(data, contains('fileTagMap'));
      expect(data, contains('highlights'));
      expect(data, contains('bookmarks'));
      expect(data, contains('settings'));
      expect(data, contains('favorites'));
      expect(data, contains('recentFiles'));
      expect(data, contains('lastReadPositions'));
    });

    test('exportAll includes populated tags', () async {
      await tagService.saveTags([
        Tag(id: 't1', name: 'Work', color: 0xFFE57373),
        Tag(id: 't2', name: 'Personal', color: 0xFF81C784),
      ]);
      await tagService.saveFileTagMap({
        '/doc1.pdf': ['t1'],
        '/doc2.pdf': ['t1', 't2'],
      });

      final json = await backupService.exportAll(recentFilePaths: []);
      final data = jsonDecode(json)['data'] as Map<String, dynamic>;

      expect((data['tags'] as List).length, equals(2));
      expect((data['fileTagMap'] as Map)['/doc1.pdf'], equals(['t1']));
      expect(
        (data['fileTagMap'] as Map)['/doc2.pdf'] as List,
        containsAll(['t1', 't2']),
      );
    });

    test('exportAll includes populated highlights', () async {
      await highlightService.saveForFile('/doc.pdf', [
        HighlightData(
          id: 'h1',
          filePath: '/doc.pdf',
          pageNumber: 1,
          text: 'hello world',
          color: 0xFFFF0000,
        ),
      ]);

      final json = await backupService.exportAll(recentFilePaths: []);
      final data = jsonDecode(json)['data'] as Map<String, dynamic>;
      final highlights = data['highlights'] as List;

      expect(highlights.length, equals(1));
      expect(highlights.first['text'], equals('hello world'));
      expect(highlights.first['color'], equals(0xFFFF0000));
    });

    test('exportAll includes populated bookmarks', () async {
      await bookmarkService.saveForFile('/doc.pdf', [
        Bookmark(
          id: 'b1',
          filePath: '/doc.pdf',
          pageNumber: 42,
          label: 'Important',
        ),
      ]);

      final json = await backupService.exportAll(recentFilePaths: []);
      final data = jsonDecode(json)['data'] as Map<String, dynamic>;
      final bookmarks = data['bookmarks'] as List;

      expect(bookmarks.length, equals(1));
      expect(bookmarks.first['pageNumber'], equals(42));
      expect(bookmarks.first['label'], equals('Important'));
    });

    test('exportAll includes settings', () async {
      await settingsService.setThemeMode('dark');
      await settingsService.setAutoEncrypt(true);
      await settingsService.setContinuousScroll(true);
      await settingsService.setDarkReadingMode(true);
      await settingsService.setShowThumbnails(false);

      final json = await backupService.exportAll(recentFilePaths: []);
      final data = jsonDecode(json)['data'] as Map<String, dynamic>;
      final settings = data['settings'] as Map<String, dynamic>;

      expect(settings['themeMode'], equals('dark'));
      expect(settings['autoEncrypt'], isTrue);
      expect(settings['continuousScroll'], isTrue);
      expect(settings['darkReadingMode'], isTrue);
      expect(settings['showThumbnails'], isFalse);
    });

    test('exportAll includes favorites and recent files', () async {
      await settingsService.setFavorite('/a.pdf', true);
      await settingsService.setFavorite('/b.pdf', true);

      final json = await backupService.exportAll(
        recentFilePaths: ['/r1.pdf', '/r2.pdf'],
      );
      final data = jsonDecode(json)['data'] as Map<String, dynamic>;
      final favorites = data['favorites'] as List;
      final recentFiles = data['recentFiles'] as List;

      expect(favorites, containsAll(['/a.pdf', '/b.pdf']));
      expect(recentFiles, equals(['/r1.pdf', '/r2.pdf']));
    });

    test('exportAll includes last read positions', () async {
      await settingsService.setLastReadPage('/doc.pdf', 15, 100);
      await settingsService.setLastReadPage('/other.pdf', 3, 50);

      final json = await backupService.exportAll(recentFilePaths: []);
      final data = jsonDecode(json)['data'] as Map<String, dynamic>;
      final lastRead = data['lastReadPositions'] as Map<String, dynamic>;

      expect(lastRead['/doc.pdf']['page'], equals(15));
      expect(lastRead['/doc.pdf']['total'], equals(100));
      expect(lastRead['/other.pdf']['page'], equals(3));
      expect(lastRead['/other.pdf']['total'], equals(50));
    });

    test('exportAll returns empty arrays when no data exists', () async {
      final json = await backupService.exportAll(recentFilePaths: []);
      final data = jsonDecode(json)['data'] as Map<String, dynamic>;

      expect(data['tags'], equals([]));
      expect(data['highlights'], equals([]));
      expect(data['bookmarks'], equals([]));
      expect(data['favorites'], equals([]));
      expect(data['recentFiles'], equals([]));
    });

    // ---------------------------------------------------------------
    // Import tests
    // ---------------------------------------------------------------

    test('importFromJson restores tags and file→tag map', () async {
      // Seed data
      await tagService.saveTags([
        Tag(id: 't1', name: 'Work', color: 0xFFE57373),
      ]);
      await tagService.saveFileTagMap({
        '/doc.pdf': ['t1'],
      });

      // Export
      final json = await backupService.exportAll(recentFilePaths: []);

      // Clear
      await tagService.saveTags([]);
      await tagService.saveFileTagMap({});
      expect(tagService.getAllTags(), isEmpty);

      // Import
      final success = await backupService.importFromJson(json);
      expect(success, isTrue);

      // Verify
      expect(tagService.getAllTags().length, equals(1));
      expect(tagService.getAllTags().first.name, equals('Work'));
      expect(
        tagService.getFileTagMap()['/doc.pdf'],
        equals(['t1']),
      );
    });

    test('importFromJson restores highlights', () async {
      await highlightService.saveForFile('/doc.pdf', [
        HighlightData(
          id: 'h1',
          filePath: '/doc.pdf',
          pageNumber: 1,
          text: 'backup test',
        ),
      ]);

      final json = await backupService.exportAll(recentFilePaths: []);
      await highlightService.saveForFile('/doc.pdf', []);

      await backupService.importFromJson(json);

      final restored = highlightService.loadForFile('/doc.pdf');
      expect(restored.length, equals(1));
      expect(restored.first.text, equals('backup test'));
    });

    test('importFromJson restores bookmarks', () async {
      await bookmarkService.saveForFile('/doc.pdf', [
        Bookmark(
          id: 'b1',
          filePath: '/doc.pdf',
          pageNumber: 10,
          label: 'Chapter 1',
        ),
      ]);

      final json = await backupService.exportAll(recentFilePaths: []);
      await bookmarkService.saveForFile('/doc.pdf', []);

      await backupService.importFromJson(json);

      final restored = bookmarkService.loadForFile('/doc.pdf');
      expect(restored.length, equals(1));
      expect(restored.first.pageNumber, equals(10));
      expect(restored.first.label, equals('Chapter 1'));
    });

    test('importFromJson restores settings', () async {
      await settingsService.setThemeMode('dark');
      await settingsService.setAutoEncrypt(true);

      final json = await backupService.exportAll(recentFilePaths: []);

      await settingsService.setThemeMode('light');
      await settingsService.setAutoEncrypt(false);

      await backupService.importFromJson(json);

      expect(settingsService.themeMode, equals('dark'));
      expect(settingsService.autoEncrypt, isTrue);
    });

    test('importFromJson restores favorites', () async {
      await settingsService.setFavorite('/a.pdf', true);
      await settingsService.setFavorite('/b.pdf', true);

      final json = await backupService.exportAll(recentFilePaths: []);

      await settingsService.setFavorite('/a.pdf', false);
      await settingsService.setFavorite('/b.pdf', false);
      expect(settingsService.getFavorites(), isEmpty);

      await backupService.importFromJson(json);

      expect(settingsService.getFavorites(), containsAll(['/a.pdf', '/b.pdf']));
    });

    test('importFromJson restores last read positions', () async {
      await settingsService.setLastReadPage('/doc.pdf', 42, 200);

      final json = await backupService.exportAll(recentFilePaths: []);

      await settingsService.setLastReadPage('/doc.pdf', 0, 0);

      await backupService.importFromJson(json);

      expect(settingsService.getLastReadPage('/doc.pdf'), equals(42));
      final progress = settingsService.getLastReadProgress('/doc.pdf');
      expect(progress?.page, equals(42));
      expect(progress?.totalPages, equals(200));
    });

    test('importFromJson returns false for incompatible version', () async {
      final badJson = jsonEncode({
        'metadata': {'version': 999, 'exportedAt': 'now'},
        'data': {},
      });

      final success = await backupService.importFromJson(badJson);
      expect(success, isFalse);
    });

    test('importFromJson returns false for malformed JSON', () async {
      final success = await backupService.importFromJson('not json');
      expect(success, isFalse);
    });

    test('full round-trip preserves all data', () async {
      // Seed everything
      await tagService.saveTags([
        Tag(id: 't1', name: 'Science', color: 0xFF64B5F6),
      ]);
      await tagService.saveFileTagMap({
        '/paper.pdf': ['t1'],
      });
      await highlightService.saveForFile('/paper.pdf', [
        HighlightData(
          id: 'h1',
          filePath: '/paper.pdf',
          pageNumber: 1,
          text: 'quantum',
          color: 0xFFFFEB3B,
        ),
      ]);
      await bookmarkService.saveForFile('/paper.pdf', [
        Bookmark(id: 'b1', filePath: '/paper.pdf', pageNumber: 5),
      ]);
      await settingsService.setThemeMode('dark');
      await settingsService.setAutoEncrypt(true);
      await settingsService.setFavorite('/paper.pdf', true);
      await settingsService.setLastReadPage('/paper.pdf', 3, 50);

      // Export
      final json = await backupService.exportAll(
        recentFilePaths: ['/paper.pdf'],
      );

      // Verify JSON structure
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['metadata']['version'], equals(1));
      expect(decoded['metadata']['exportedAt'], isA<String>());

      // Clear everything
      await tagService.saveTags([]);
      await tagService.saveFileTagMap({});
      await highlightService.saveForFile('/paper.pdf', []);
      await bookmarkService.saveForFile('/paper.pdf', []);
      await settingsService.setThemeMode('system');
      await settingsService.setAutoEncrypt(false);
      await settingsService.setFavorite('/paper.pdf', false);
      await settingsService.setLastReadPage('/paper.pdf', 0, 0);

      // Import
      final success = await backupService.importFromJson(json);
      expect(success, isTrue);

      // Verify everything restored
      expect(tagService.getAllTags().length, equals(1));
      expect(tagService.getAllTags().first.name, equals('Science'));
      expect(
        tagService.getFileTagMap()['/paper.pdf'],
        equals(['t1']),
      );
      expect(highlightService.loadForFile('/paper.pdf').length, equals(1));
      expect(
        highlightService.loadForFile('/paper.pdf').first.text,
        equals('quantum'),
      );
      expect(bookmarkService.loadForFile('/paper.pdf').length, equals(1));
      expect(settingsService.themeMode, equals('dark'));
      expect(settingsService.autoEncrypt, isTrue);
      expect(settingsService.getFavorites(), contains('/paper.pdf'));
    });
  });
}
