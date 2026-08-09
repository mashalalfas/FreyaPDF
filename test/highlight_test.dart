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

    test('toggleHighlightMode toggles rectangle draw mode', () {
      expect(provider.highlightMode, false);
      expect(provider.highlightModeValue, 'off');

      provider.toggleHighlightMode();
      expect(provider.highlightMode, true);
      expect(provider.highlightModeValue, 'rectangle');

      provider.toggleHighlightMode();
      expect(provider.highlightMode, false);
      expect(provider.highlightModeValue, 'off');
    });

    test('togglePanel flips state', () {
      expect(provider.showPanel, false);
      provider.togglePanel();
      expect(provider.showPanel, true);
      provider.togglePanel();
      expect(provider.showPanel, false);
    });

    test('closeFile clears file state', () async {
      await provider.addHighlight(
        HighlightData(filePath: '/test.pdf', pageNumber: 1, text: 'some text'),
      );
      provider.openFile('/test.pdf');
      expect(provider.highlightCount, 1);
      expect(provider.highlightMode, false);

      provider.toggleHighlightMode();
      expect(provider.highlightMode, true);

      provider.closeFile();

      expect(provider.fileHighlights, isEmpty);
      expect(provider.highlightMode, false);
      expect(provider.highlightModeValue, 'off');
      expect(provider.showPanel, false);
    });

    test('multiple files handled correctly', () async {
      // Add highlights for two different files
      await provider.addHighlight(
        HighlightData(
          id: 'a',
          filePath: '/a.pdf',
          pageNumber: 1,
          text: 'from a',
        ),
      );
      await provider.addHighlight(
        HighlightData(
          id: 'b',
          filePath: '/b.pdf',
          pageNumber: 2,
          text: 'from b',
        ),
      );

      expect(provider.allHighlights, hasLength(2));

      provider.openFile('/a.pdf');
      expect(provider.highlightCount, 1);
      expect(provider.fileHighlights.first.text, 'from a');

      provider.openFile('/b.pdf');
      expect(provider.highlightCount, 1);
      expect(provider.fileHighlights.first.text, 'from b');
    });

    test('setHighlightModeBool uses legacy boolean interface', () {
      expect(provider.highlightModeValue, 'off');

      provider.setHighlightModeBool(true);
      expect(provider.highlightModeValue, 'rectangle');
      expect(provider.highlightMode, true);

      provider.setHighlightModeBool(false);
      expect(provider.highlightModeValue, 'off');
      expect(provider.highlightMode, false);
    });

    test('isRectangleDrawMode reflects mode', () {
      expect(provider.isRectangleDrawMode, false);

      provider.setHighlightMode('rectangle');
      expect(provider.isRectangleDrawMode, true);
      expect(provider.highlightMode, true);

      provider.setHighlightMode('text');
      expect(provider.isRectangleDrawMode, false);
      expect(provider.highlightMode, true);
    });
  });

  group('HighlightData rectangle type', () {
    test('defaults to text type', () {
      final h = HighlightData(
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'hello',
      );

      expect(h.type, 'text');
      expect(h.isRectangle, false);
      expect(h.rectLeft, isNull);
      expect(h.rectTop, isNull);
      expect(h.rectRight, isNull);
      expect(h.rectBottom, isNull);
    });

    test('rectangle highlight stores coordinates', () {
      final h = HighlightData(
        filePath: '/test.pdf',
        pageNumber: 5,
        text: '',
        type: 'rectangle',
        rectLeft: 100.0,
        rectTop: 200.0,
        rectRight: 300.0,
        rectBottom: 400.0,
      );

      expect(h.type, 'rectangle');
      expect(h.isRectangle, true);
      expect(h.rectLeft, 100.0);
      expect(h.rectTop, 200.0);
      expect(h.rectRight, 300.0);
      expect(h.rectBottom, 400.0);
    });

    test('rectangle highlight serializes and deserializes', () {
      final h = HighlightData(
        id: 'rect-1',
        filePath: '/test.pdf',
        pageNumber: 3,
        text: '',
        type: 'rectangle',
        rectLeft: 50.0,
        rectTop: 100.0,
        rectRight: 250.0,
        rectBottom: 350.0,
        color: 0xFF00FF00,
      );

      final json = h.toJson();
      expect(json['type'], 'rectangle');
      expect(json['rectLeft'], 50.0);
      expect(json['rectTop'], 100.0);
      expect(json['rectRight'], 250.0);
      expect(json['rectBottom'], 350.0);

      final restored = HighlightData.fromJson(json);
      expect(restored.type, 'rectangle');
      expect(restored.isRectangle, true);
      expect(restored.rectLeft, 50.0);
      expect(restored.rectTop, 100.0);
      expect(restored.rectRight, 250.0);
      expect(restored.rectBottom, 350.0);
    });

    test('backward compatibility: JSON without type defaults to text', () {
      // Simulate old JSON that has no 'type' field
      final json = {
        'id': 'old-hl',
        'filePath': '/test.pdf',
        'pageNumber': 1,
        'text': 'old highlight',
        'color': 0xFFFFEB3B,
        'createdAt': DateTime(2025, 1, 1).millisecondsSinceEpoch,
      };

      final restored = HighlightData.fromJson(json);
      expect(restored.type, 'text');
      expect(restored.isRectangle, false);
    });

    test('copyWith preserves rectangle fields', () {
      final h = HighlightData(
        filePath: '/test.pdf',
        pageNumber: 1,
        text: '',
        type: 'rectangle',
        rectLeft: 10.0,
        rectTop: 20.0,
        rectRight: 110.0,
        rectBottom: 120.0,
      );

      final modified = h.copyWith(color: 0xFF0000FF);
      expect(modified.type, 'rectangle');
      expect(modified.isRectangle, true);
      expect(modified.rectLeft, 10.0);
      expect(modified.rectTop, 20.0);
      expect(modified.color, 0xFF0000FF);
    });

    test('equality includes type field', () {
      final textH = HighlightData(
        id: 'same',
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'hello',
        type: 'text',
      );
      final rectH = HighlightData(
        id: 'same',
        filePath: '/test.pdf',
        pageNumber: 1,
        text: 'hello',
        type: 'rectangle',
      );

      expect(textH, isNot(equals(rectH)));
    });
  });
}
