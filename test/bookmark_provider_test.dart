// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/features/bookmarks/bookmark.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_service.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_provider.dart';

void main() {
  group('BookmarkProvider', () {
    late SharedPreferences prefs;
    late BookmarkService service;
    late BookmarkProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = BookmarkService(prefs);
      provider = BookmarkProvider(service);
    });

    test('starts empty', () {
      expect(provider.allBookmarks, isEmpty);
      expect(provider.fileBookmarks, isEmpty);
      expect(provider.bookmarkCount, 0);
      expect(provider.showPanel, false);
    });

    test('openFile loads bookmarks for that file', () async {
      // Pre-save some bookmarks
      await service.saveForFile('/test.pdf', [
        Bookmark(
          id: 'bm_1',
          filePath: '/test.pdf',
          pageNumber: 1,
          label: 'existing',
        ),
      ]);

      // Re-create the provider so it picks up stored data
      provider = BookmarkProvider(service);
      provider.openFile('/test.pdf');

      expect(provider.fileBookmarks, hasLength(1));
      expect(provider.fileBookmarks.first.label, 'existing');
    });

    test('addBookmark creates and persists a bookmark', () async {
      final bm = Bookmark(
        filePath: '/test.pdf',
        pageNumber: 1,
        label: 'New bookmark',
      );

      await provider.addBookmark(bm);

      expect(provider.allBookmarks, hasLength(1));
      expect(provider.allBookmarks.first.label, 'New bookmark');

      // Verify persistence
      final loaded = service.loadForFile('/test.pdf');
      expect(loaded, hasLength(1));
      expect(loaded.first.label, 'New bookmark');
    });

    test('addBookmark updates fileBookmarks when file is open', () async {
      provider.openFile('/test.pdf');

      final bm = Bookmark(
        filePath: '/test.pdf',
        pageNumber: 1,
        label: 'New bookmark',
      );

      await provider.addBookmark(bm);

      expect(provider.bookmarkCount, 1);
      expect(provider.fileBookmarks.first.label, 'New bookmark');
    });

    test('removeBookmark deletes and persists', () async {
      provider.openFile('/test.pdf');

      final bm = Bookmark(
        id: 'delete-me',
        filePath: '/test.pdf',
        pageNumber: 1,
        label: 'To delete',
      );

      await provider.addBookmark(bm);
      expect(provider.bookmarkCount, 1);

      await provider.removeBookmark('delete-me');
      expect(provider.bookmarkCount, 0);
      expect(service.loadForFile('/test.pdf'), isEmpty);
    });

    test('renameBookmark updates label in memory and storage', () async {
      provider.openFile('/test.pdf');

      final bm = Bookmark(
        id: 'rename-me',
        filePath: '/test.pdf',
        pageNumber: 1,
        label: 'Old name',
      );

      await provider.addBookmark(bm);
      await provider.renameBookmark('rename-me', 'New name');

      expect(provider.fileBookmarks.first.label, 'New name');

      // Verify persistence
      final loaded = service.loadForFile('/test.pdf');
      expect(loaded.first.label, 'New name');
    });

    test('renameBookmark does nothing for non-existent ID', () async {
      provider.openFile('/test.pdf');

      await provider.addBookmark(Bookmark(
        id: 'only',
        filePath: '/test.pdf',
        pageNumber: 1,
        label: 'Only',
      ));

      await provider.renameBookmark('nonexistent', 'Should not appear');

      expect(provider.fileBookmarks.first.label, 'Only');
    });

    test('isPageBookmarked returns correct boolean', () async {
      provider.openFile('/test.pdf');

      await provider.addBookmark(Bookmark(
        id: 'bm_1',
        filePath: '/test.pdf',
        pageNumber: 3,
        label: 'Page 3',
      ));

      expect(provider.isPageBookmarked(3), isTrue);
      expect(provider.isPageBookmarked(1), isFalse);
      expect(provider.isPageBookmarked(5), isFalse);

      // Add another bookmark
      await provider.addBookmark(Bookmark(
        id: 'bm_2',
        filePath: '/test.pdf',
        pageNumber: 5,
        label: 'Page 5',
      ));

      expect(provider.isPageBookmarked(3), isTrue);
      expect(provider.isPageBookmarked(5), isTrue);
      expect(provider.isPageBookmarked(1), isFalse);
    });

    test('isPageBookmarked returns false when no file is open', () {
      expect(provider.isPageBookmarked(1), isFalse);
    });

    test('forgetFile removes all bookmarks for a file', () async {
      // Add bookmarks for two files
      await provider.addBookmark(Bookmark(
        id: 'a1',
        filePath: '/a.pdf',
        pageNumber: 1,
        label: 'From A',
      ));
      await provider.addBookmark(Bookmark(
        id: 'b1',
        filePath: '/b.pdf',
        pageNumber: 1,
        label: 'From B',
      ));

      expect(provider.allBookmarks, hasLength(2));

      await provider.forgetFile('/a.pdf');

      expect(provider.allBookmarks, hasLength(1));
      expect(provider.allBookmarks.first.filePath, '/b.pdf');
      expect(service.loadForFile('/a.pdf'), isEmpty);
      expect(service.loadForFile('/b.pdf'), hasLength(1));
    });

    test('forgetFile clears fileBookmarks when current file is forgotten', () async {
      provider.openFile('/test.pdf');

      await provider.addBookmark(Bookmark(
        id: 'bm_1',
        filePath: '/test.pdf',
        pageNumber: 1,
        label: 'To forget',
      ));

      expect(provider.fileBookmarks, hasLength(1));

      await provider.forgetFile('/test.pdf');

      expect(provider.fileBookmarks, isEmpty);
      expect(provider.allBookmarks, isEmpty);
    });

    test('renameFile updates file paths on matching bookmarks', () async {
      await provider.addBookmark(Bookmark(
        id: 'a1',
        filePath: '/old.pdf',
        pageNumber: 1,
        label: 'Renamed file',
      ));
      await provider.addBookmark(Bookmark(
        id: 'b1',
        filePath: '/other.pdf',
        pageNumber: 1,
        label: 'Other file',
      ));

      await provider.renameFile('/old.pdf', '/new.pdf');

      expect(provider.allBookmarks, hasLength(2));
      final renamed = provider.allBookmarks.firstWhere((b) => b.id == 'a1');
      expect(renamed.filePath, '/new.pdf');

      // Other file unchanged
      final other = provider.allBookmarks.firstWhere((b) => b.id == 'b1');
      expect(other.filePath, '/other.pdf');

      // Storage updated
      expect(service.loadForFile('/old.pdf'), isEmpty);
      expect(service.loadForFile('/new.pdf'), hasLength(1));
      expect(service.loadForFile('/new.pdf').first.label, 'Renamed file');
    });

    test('renameFile updates currentFilePath when renaming the open file', () async {
      provider.openFile('/old.pdf');

      await provider.addBookmark(Bookmark(
        id: 'bm_1',
        filePath: '/old.pdf',
        pageNumber: 1,
        label: 'Open file',
      ));

      await provider.renameFile('/old.pdf', '/new.pdf');

      // fileBookmarks should now point to the new path
      expect(provider.fileBookmarks, hasLength(1));
      expect(provider.fileBookmarks.first.filePath, '/new.pdf');
    });

    test('renameFile does nothing when no bookmarks match', () async {
      await provider.addBookmark(Bookmark(
        id: 'bm_1',
        filePath: '/existing.pdf',
        pageNumber: 1,
        label: 'Existing',
      ));

      // Should not throw and should not change anything
      await provider.renameFile('/nonexistent.pdf', '/new.pdf');

      expect(provider.allBookmarks, hasLength(1));
      expect(provider.allBookmarks.first.filePath, '/existing.pdf');
    });

    test('closeFile clears file-specific state', () async {
      await provider.addBookmark(Bookmark(
        id: 'bm_1',
        filePath: '/test.pdf',
        pageNumber: 1,
        label: 'File specific',
      ));
      provider.openFile('/test.pdf');
      expect(provider.fileBookmarks, hasLength(1));

      provider.closeFile();

      expect(provider.fileBookmarks, isEmpty);
      expect(provider.showPanel, false);
      // All bookmarks preserved
      expect(provider.allBookmarks, hasLength(1));
    });

    test('togglePanel flips state', () {
      expect(provider.showPanel, false);
      provider.togglePanel();
      expect(provider.showPanel, true);
      provider.togglePanel();
      expect(provider.showPanel, false);
    });

    test('setShowPanel sets state explicitly', () {
      provider.setShowPanel(true);
      expect(provider.showPanel, true);

      provider.setShowPanel(true);
      expect(provider.showPanel, true); // no change

      provider.setShowPanel(false);
      expect(provider.showPanel, false);
    });

    test('multiple files handled correctly in fileBookmarks', () async {
      await provider.addBookmark(Bookmark(
        id: 'a',
        filePath: '/a.pdf',
        pageNumber: 1,
        label: 'from a',
      ));
      await provider.addBookmark(Bookmark(
        id: 'b',
        filePath: '/b.pdf',
        pageNumber: 2,
        label: 'from b',
      ));

      expect(provider.allBookmarks, hasLength(2));

      provider.openFile('/a.pdf');
      expect(provider.bookmarkCount, 1);
      expect(provider.fileBookmarks.first.label, 'from a');

      provider.openFile('/b.pdf');
      expect(provider.bookmarkCount, 1);
      expect(provider.fileBookmarks.first.label, 'from b');
    });
  });
}
