import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:feya_pdf/features/highlights/highlight.dart';
import 'package:feya_pdf/features/highlights/highlight_service.dart';
import 'package:feya_pdf/features/highlights/highlight_provider.dart';

void main() {
  group('HighlightData model', () {
    test('creates highlight with default values', () {
      final h = HighlightData(
        filePath: '/test/file.pdf',
        pageNumber: 1,
        text: 'hello world',
      );

      expect(h.id, isNotEmpty);
      expect(h.filePath, '/test/file.pdf');
      expect(h.pageNumber, 1);
      expect(h.text, 'hello world');
      expect(h.color, 0xFFFFEB3B); // default yellow
      expect(h.createdAt, isNotNull);
    });

    test('serializes and deserializes to/from JSON', () {
      final h = HighlightData(
        id: 'test-123',
        filePath: '/test/file.pdf',
        pageNumber: 3,
        text: 'highlighted text',
        color: 0xFFFF0000,
        createdAt: DateTime(2025, 1, 15),
      );

      final json = h.toJson();
      final restored = HighlightData.fromJson(json);

      expect(restored.id, 'test-123');
      expect(restored.filePath, '/test/file.pdf');
      expect(restored.pageNumber, 3);
      expect(restored.text, 'highlighted text');
      expect(restored.color, 0xFFFF0000);
      expect(restored.createdAt, DateTime(2025, 1, 15));
    });

    test('equality works correctly', () {
      final h1 = HighlightData(
        id: 'id1',
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'test',
      );
      final h2 = HighlightData(
        id: 'id1',
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'test',
      );
      final h3 = HighlightData(
        id: 'id2',
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'test',
      );

      expect(h1, equals(h2));
      expect(h1, isNot(equals(h3)));
    });

    test('copyWith creates modified copy', () {
      final h = HighlightData(
        filePath: '/a.pdf',
        pageNumber: 1,
        text: 'original',
      );

      final modified = h.copyWith(text: 'modified', pageNumber: 2);

      expect(modified.id, h.id);
      expect(modified.filePath, '/a.pdf');
      expect(modified.pageNumber, 2);
      expect(modified.text, 'modified');
    });
  });

  group('HighlightService', () {
    late SharedPreferences prefs;
    late HighlightService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = HighlightService(prefs);
    });

    test('loadAll returns empty list when nothing stored', () {
      expect(service.loadAll(), isEmpty);
    });

    test('saveForFile and loadForFile round-trips highlights', () async {
      final highlights = [
        HighlightData(
          id: 'h1',
          filePath: '/test.pdf',
          pageNumber: 1,
          text: 'first highlight',
        ),
        HighlightData(
          id: 'h2',
          filePath: '/test.pdf',
          pageNumber: 2,
          text: 'second highlight',
        ),
      ];

      await service.saveForFile('/test.pdf', highlights);

      final loaded = service.loadForFile('/test.pdf');
      expect(loaded.length, 2);
      expect(loaded[0].text, 'first highlight');
      expect(loaded[1].text, 'second highlight');
    });

    test('multiple files stored independently', () async {
      final h1 = [
        HighlightData(
          id: 'a1',
          filePath: '/a.pdf',
          pageNumber: 1,
          text: 'from a',
        ),
      ];
      final h2 = [
        HighlightData(
          id: 'b1',
          filePath: '/b.pdf',
          pageNumber: 1,
          text: 'from b',
        ),
      ];

      await service.saveForFile('/a.pdf', h1);
      await service.saveForFile('/b.pdf', h2);

      expect(service.loadForFile('/a.pdf'), hasLength(1));
      expect(service.loadForFile('/b.pdf'), hasLength(1));
      expect(service.loadForFile('/a.pdf').first.text, 'from a');
      expect(service.loadForFile('/b.pdf').first.text, 'from b');
    });

    test('deleteHighlight removes highlight by id', () async {
      final highlights = [
        HighlightData(
          id: 'keep',
          filePath: '/test.pdf',
          pageNumber: 1,
          text: 'keep me',
        ),
        HighlightData(
          id: 'remove',
          filePath: '/test.pdf',
          pageNumber: 1,
          text: 'remove me',
        ),
      ];

      await service.saveForFile('/test.pdf', highlights);
      await service.deleteHighlight('remove');

      final remaining = service.loadForFile('/test.pdf');
      expect(remaining, hasLength(1));
      expect(remaining.first.id, 'keep');
    });
  });

  group('HighlightProvider', () {
    late SharedPreferences prefs;
    late HighlightService service;
    late HighlightProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = HighlightService(prefs);
      provider = HighlightProvider(service);
    });

    test('starts empty', () {
      expect(provider.allHighlights, isEmpty);
      expect(provider.fileHighlights, isEmpty);
      expect(provider.highlightMode, false);
      expect(provider.showPanel, false);
      expect(provider.highlightCount, 0);
    });

    test('openFile loads highlights for that file', () async {
      // Pre-save some highlights
      await service.saveForFile('/test.pdf', [
        HighlightData(
          id: 'h1',
          filePath: '/test.pdf',
          pageNumber: 1,
          text: 'existing',
        ),
      ]);

      // Re-create the provider so it picks up stored data
      provider = HighlightProvider(service);
      provider.openFile('/test.pdf');

      expect(provider.fileHighlights, hasLength(1));
      expect(provider.fileHighlights.first.text, 'existing');
    });

    test('addHighlight creates and persists a highlight', () async {
      final h = HighlightData(
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'new highlight',
      );

      await provider.addHighlight(h);

      expect(provider.allHighlights, hasLength(1));

      // Verify persistence
      final loaded = service.loadForFile('/test.pdf');
      expect(loaded, hasLength(1));
      expect(loaded.first.text, 'new highlight');
    });

    test('addHighlight updates fileHighlights when file is open', () async {
      provider.openFile('/test.pdf');

      final h = HighlightData(
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'new highlight',
      );

      await provider.addHighlight(h);

      expect(provider.highlightCount, 1);
      expect(provider.fileHighlights.first.text, 'new highlight');
    });

    test('removeHighlight deletes and persists', () async {
      provider.openFile('/test.pdf');

      final h = HighlightData(
        id: 'delete-me',
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'to delete',
      );

      await provider.addHighlight(h);
      expect(provider.highlightCount, 1);

      await provider.removeHighlight('delete-me');
      expect(provider.highlightCount, 0);
      expect(service.loadForFile('/test.pdf'), isEmpty);
    });

    test('toggleHighlightMode flips state', () {
      expect(provider.highlightMode, false);
      provider.toggleHighlightMode();
      expect(provider.highlightMode, true);
      provider.toggleHighlightMode();
      expect(provider.highlightMode, false);
    });

    test('togglePanel flips state', () {
      expect(provider.showPanel, false);
      provider.togglePanel();
      expect(provider.showPanel, true);
      provider.togglePanel();
      expect(provider.showPanel, false);
    });

    test('closeFile clears file state', () async {
      await provider.addHighlight(HighlightData(
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'some text',
      ));
      provider.openFile('/test.pdf');
      expect(provider.highlightCount, 1);
      expect(provider.highlightMode, false);

      provider.toggleHighlightMode();
      expect(provider.highlightMode, true);

      provider.closeFile();

      expect(provider.fileHighlights, isEmpty);
      expect(provider.highlightMode, false);
      expect(provider.showPanel, false);
    });

    test('multiple files handled correctly', () async {
      // Add highlights for two different files
      await provider.addHighlight(HighlightData(
        id: 'a',
        filePath: '/a.pdf',
        pageNumber: 1,
        text: 'from a',
      ));
      await provider.addHighlight(HighlightData(
        id: 'b',
        filePath: '/b.pdf',
        pageNumber: 2,
        text: 'from b',
      ));

      expect(provider.allHighlights, hasLength(2));

      provider.openFile('/a.pdf');
      expect(provider.highlightCount, 1);
      expect(provider.fileHighlights.first.text, 'from a');

      provider.openFile('/b.pdf');
      expect(provider.highlightCount, 1);
      expect(provider.fileHighlights.first.text, 'from b');
    });
  });
}
