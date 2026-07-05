// Size: small — pure service tests backed by mock SharedPreferences (no I/O, milliseconds)

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/features/tags/tag.dart';
import 'package:feya_pdf/features/tags/tag_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TagService', () {
    late TagService service;

    setUp(() async {
      // Reset SharedPreferences mock for each test
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      service = TagService(prefs);
    });

    // Arrange: fresh TagService with empty prefs (setUp resets mock)
    // Act: getAllTags()
    // Assert: returns empty list
    test('getAllTags returns empty list when nothing stored', () {
      expect(service.getAllTags(), isEmpty);
    });

    // Arrange: two Tag objects
    // Act: saveTags then getAllTags
    // Assert: round-trip produces equal list
    test('saveTags then getAllTags round-trips correctly', () async {
      final tags = [
        Tag(id: 't1', name: 'Work', color: 0xFFE57373),
        Tag(id: 't2', name: 'Personal', color: 0xFF81C784),
      ];
      await service.saveTags(tags);
      expect(service.getAllTags(), equals(tags));
    });

    // Arrange: save one tag, then save a different set
    // Act: getAllTags()
    // Assert: only the second set remains (length 1, id='new')
    test('saveTags replaces all existing stored tags', () async {
      await service.saveTags([Tag(id: 'old', name: 'Old', color: 0)]);
      await service.saveTags([Tag(id: 'new', name: 'New', color: 1)]);
      expect(service.getAllTags(), hasLength(1));
      expect(service.getAllTags().first.id, equals('new'));
    });

    // Arrange: mock prefs with non-list JSON stored under mely_pdf_tags
    // Act: getAllTags()
    // Assert: returns empty list (graceful corruption handling)
    test('getAllTags returns empty list for corrupt JSON that is not a list', () async {
      SharedPreferences.setMockInitialValues({'mely_pdf_tags': '{"bad": true}'});
      final prefs = await SharedPreferences.getInstance();
      final svc = TagService(prefs);
      expect(svc.getAllTags(), isEmpty);
    });

    // Arrange: mock prefs with completely unparseable string
    // Act: getAllTags()
    // Assert: returns empty list (graceful corruption handling)
    test('getAllTags returns empty list for completely corrupt string', () async {
      SharedPreferences.setMockInitialValues({'mely_pdf_tags': 'not json at all'});
      final prefs = await SharedPreferences.getInstance();
      final svc = TagService(prefs);
      expect(svc.getAllTags(), isEmpty);
    });

    // Arrange: fresh TagService with empty prefs
    // Act: getFileTagMap()
    // Assert: returns empty map
    test('getFileTagMap returns empty map when nothing stored', () {
      expect(service.getFileTagMap(), isEmpty);
    });

    // Arrange: a file-tag map with two entries
    // Act: saveFileTagMap then getFileTagMap
    // Assert: round-trip produces equal map
    test('saveFileTagMap then getFileTagMap round-trips correctly', () async {
      final map = {
        '/path/to/file.pdf': ['t1', 't2'],
        '/path/to/other.pdf': ['t1'],
      };
      await service.saveFileTagMap(map);
      expect(service.getFileTagMap(), equals(map));
    });

    // Arrange: save one mapping, then save a different one
    // Act: getFileTagMap()
    // Assert: only the second mapping remains (length 1, key='/b.pdf')
    test('saveFileTagMap replaces all existing stored mappings', () async {
      await service.saveFileTagMap({'/a.pdf': ['t1']});
      await service.saveFileTagMap({'/b.pdf': ['t2']});
      expect(service.getFileTagMap(), hasLength(1));
      expect(service.getFileTagMap().keys.first, equals('/b.pdf'));
    });

    // Arrange: mock prefs with non-map JSON stored under mely_pdf_file_tags
    // Act: getFileTagMap()
    // Assert: returns empty map (graceful corruption handling)
    test('getFileTagMap returns empty map for corrupt JSON that is not a map', () async {
      SharedPreferences.setMockInitialValues({'mely_pdf_file_tags': '[1,2,3]'});
      final prefs = await SharedPreferences.getInstance();
      final svc = TagService(prefs);
      expect(svc.getFileTagMap(), isEmpty);
    });

    // Arrange: mock prefs with file-tag map containing an int in a tag list ['t1', 42, 't2']
    // Act: getFileTagMap()
    // Assert: int entry is filtered out, only strings remain ['t1', 't2']
    test('getFileTagMap filters out non-string values in list entries', () async {
      // List contains an int entry which should be filtered out by whereType
      final raw = jsonEncode({'/file.pdf': ['t1', 42, 't2']});
      SharedPreferences.setMockInitialValues({'mely_pdf_file_tags': raw});
      final prefs = await SharedPreferences.getInstance();
      final svc = TagService(prefs);
      final result = svc.getFileTagMap();
      expect(result['/file.pdf'], equals(['t1', 't2']));
    });
  });
}
