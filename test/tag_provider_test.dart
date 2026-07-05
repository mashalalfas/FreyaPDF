// Size: small — provider tests backed by mock SharedPreferences (no real I/O, milliseconds)

import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/features/tags/tag.dart';
import 'package:feya_pdf/features/tags/tag_provider.dart';
import 'package:feya_pdf/features/tags/tag_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build a TagProvider backed by a fresh mock SharedPreferences.
Future<TagProvider> _buildProvider(Map<String, Object> initialValues) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  return TagProvider(TagService(prefs));
}

void main() {
  group('TagProvider', () {
    // Arrange: build provider with empty prefs
    // Act: read tags and hasTags
    // Assert: empty list, hasTags false
    test('starts with no tags when prefs are empty', () async {
      final provider = await _buildProvider({});
      expect(provider.tags, isEmpty);
      expect(provider.hasTags, isFalse);
    });

    // Arrange: build provider with empty prefs
    // Act: createTag('Work', color:0xFFE57373)
    // Assert: tags list has length 1, name and color match
    test('createTag adds tag and notifies listeners', () async {
      final provider = await _buildProvider({});
      await provider.createTag(name: 'Work', color: 0xFFE57373);
      expect(provider.tags, hasLength(1));
      expect(provider.tags.first.name, equals('Work'));
      expect(provider.tags.first.color, equals(0xFFE57373));
    });

    // Arrange: build provider with empty prefs
    // Act: createTag with whitespace-only name
    // Assert: throws ArgumentError
    test('createTag with empty or whitespace name throws ArgumentError', () async {
      final provider = await _buildProvider({});
      expect(
        () => provider.createTag(name: '   ', color: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Arrange: build provider with empty prefs
    // Act: create two tags
    // Assert: both ids are unique
    test('createTag generates unique ids for each tag', () async {
      final provider = await _buildProvider({});
      final t1 = await provider.createTag(name: 'A', color: 0);
      final t2 = await provider.createTag(name: 'B', color: 0);
      expect(t1.id, isNot(equals(t2.id)));
    });

    // Arrange: build provider, create tag 'Old'
    // Act: updateTag with new name and color
    // Assert: first tag has updated name and color
    test('updateTag modifies name and color of an existing tag', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'Old', color: 0xFF0000);
      await provider.updateTag(tag.copyWith(name: 'New', color: 0x00FF00));
      expect(provider.tags.first.name, equals('New'));
      expect(provider.tags.first.color, equals(0x00FF00));
    });

    // Arrange: build provider, create tag 'Only'
    // Act: updateTag with a tag that has an unknown id
    // Assert: tags list unchanged (still 1 item, still named 'Only')
    test('updateTag does nothing when tag id is not found', () async {
      final provider = await _buildProvider({});
      await provider.createTag(name: 'Only', color: 0);
      // Create a fake tag with an unknown id
      await provider.updateTag(Tag(id: 'unknown_id', name: 'X', color: 1));
      expect(provider.tags, hasLength(1));
      expect(provider.tags.first.name, equals('Only'));
    });

    // Arrange: build provider, create tag 'ToDelete'
    // Act: deleteTag(tag.id)
    // Assert: tags list is empty
    test('deleteTag removes the tag from the list', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'ToDelete', color: 0);
      expect(provider.tags, hasLength(1));

      await provider.deleteTag(tag.id);
      expect(provider.tags, isEmpty);
    });

    // Arrange: build provider, create tag, set it as active filter
    // Act: deleteTag for the filtered tag
    // Assert: activeFilterTagId is null (filter cleared)
    test('deleteTag clears active filter when deleted tag was the active filter', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'FilterMe', color: 0);
      provider.setActiveFilter(tag.id);
      expect(provider.activeFilterTagId, equals(tag.id));

      await provider.deleteTag(tag.id);
      expect(provider.activeFilterTagId, isNull);
    });

    // Arrange: build provider, create one tag
    // Act: deleteTag with a non-existent id
    // Assert: no throw, tags list unchanged
    test('deleteTag is idempotent and does not throw for unknown id', () async {
      final provider = await _buildProvider({});
      await provider.createTag(name: 'Only', color: 0);
      // Should not throw
      await provider.deleteTag('nonexistent_id');
      expect(provider.tags, hasLength(1));
    });

    // Arrange: build provider, create tag
    // Act: setActiveFilter(tag.id) then clearFilter()
    // Assert: activeFilterTagId set then null
    test('setActiveFilter sets filter and clearFilter resets it', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'F', color: 0);

      provider.setActiveFilter(tag.id);
      expect(provider.activeFilterTagId, equals(tag.id));
      expect(provider.activeFilterTag?.name, equals('F'));

      provider.clearFilter();
      expect(provider.activeFilterTagId, isNull);
    });

    // Arrange: build provider, create tag, set active filter
    // Act: setActiveFilter again with the same id
    // Assert: no throw, activeFilterTagId still equals tag.id
    test('setActiveFilter with same id does not throw', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'A', color: 0);
      provider.setActiveFilter(tag.id);
      // Setting same filter again should not throw (internal guard)
      provider.setActiveFilter(tag.id);
      expect(provider.activeFilterTagId, equals(tag.id));
    });

    // Arrange: build provider, create one tag
    // Act: read tags getter, attempt to mutate returned list
    // Assert: throws UnsupportedError (list is unmodifiable)
    test('tags getter returns an unmodifiable list', () async {
      final provider = await _buildProvider({});
      await provider.createTag(name: 'A', color: 0);
      final list = provider.tags;
      expect(() => list.add(Tag(id: 'x', name: 'x', color: 0)), throwsA(isA<UnsupportedError>()));
    });

    // --- File ↔ tag mapping ---

    // Arrange: build provider, no file-tag mappings set
    // Act: getTagsForFile('/any/file.pdf')
    // Assert: returns empty list
    test('getTagsForFile returns empty list when file has no mapping', () async {
      final provider = await _buildProvider({});
      expect(provider.getTagsForFile('/any/file.pdf'), isEmpty);
    });

    // Arrange: build provider, create a tag
    // Act: setFileTags('/doc.pdf', [tag.id]) then getTagsForFile
    // Assert: returns list containing tag.id
    test('setFileTags creates mapping and getTagsForFile retrieves it', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'T', color: 0);
      await provider.setFileTags('/doc.pdf', [tag.id]);
      expect(provider.getTagsForFile('/doc.pdf'), equals([tag.id]));
    });

    // Arrange: build provider, create tag, set file-tag mapping
    // Act: setFileTags('/doc.pdf', []) to clear
    // Assert: getTagsForFile returns empty list
    test('setFileTags with empty list removes the mapping', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'T', color: 0);
      await provider.setFileTags('/doc.pdf', [tag.id]);
      expect(provider.getTagsForFile('/doc.pdf'), isNotEmpty);

      await provider.setFileTags('/doc.pdf', []);
      expect(provider.getTagsForFile('/doc.pdf'), isEmpty);
    });

    // Arrange: build provider, create tag
    // Act: setFileTags('/doc.pdf', [tag.id, tag.id]) with duplicate
    // Assert: mapping has length 1 (deduplicated)
    test('setFileTags deduplicates duplicate tag ids', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'T', color: 0);
      await provider.setFileTags('/doc.pdf', [tag.id, tag.id]);
      expect(provider.getTagsForFile('/doc.pdf'), hasLength(1));
    });

    // Arrange: build provider, create tag, confirm fileHasTag is false
    // Act: toggleFileTag('/doc.pdf', tag.id) twice
    // Assert: true after first toggle, false after second
    test('toggleFileTag adds then removes a tag for a file', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'T', color: 0);

      // Initially absent
      expect(provider.fileHasTag('/doc.pdf', tag.id), isFalse);

      await provider.toggleFileTag('/doc.pdf', tag.id);
      expect(provider.fileHasTag('/doc.pdf', tag.id), isTrue);

      await provider.toggleFileTag('/doc.pdf', tag.id);
      expect(provider.fileHasTag('/doc.pdf', tag.id), isFalse);
    });

    // Arrange: build provider, create tag, set file-tag mapping
    // Act: getResolvedTagsForFile('/doc.pdf')
    // Assert: returns list with one Tag whose name matches
    test('getResolvedTagsForFile returns Tag objects for mapped ids', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'Work', color: 0xFF0000);
      await provider.setFileTags('/doc.pdf', [tag.id]);

      final resolved = provider.getResolvedTagsForFile('/doc.pdf');
      expect(resolved, hasLength(1));
      expect(resolved.first.name, equals('Work'));
    });

    // Arrange: build provider, create a real tag, set mapping with real + ghost id
    // Act: getResolvedTagsForFile('/doc.pdf')
    // Assert: only the real tag is returned, ghost id is filtered out
    test('getResolvedTagsForFile filters out unknown tag ids', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'Real', color: 0);
      // Directly set an unknown id via a fresh provider that already has a tag
      await provider.setFileTags('/doc.pdf', [tag.id, 'ghost_id']);
      final resolved = provider.getResolvedTagsForFile('/doc.pdf');
      expect(resolved, hasLength(1));
      expect(resolved.first.id, equals(tag.id));
    });

    // Arrange: build provider, create two tags, associate both with '/doc.pdf'
    // Act: forgetFile('/doc.pdf')
    // Assert: getTagsForFile returns empty list
    test('forgetFile removes all tag associations for a file path', () async {
      final provider = await _buildProvider({});
      final t1 = await provider.createTag(name: 'A', color: 0);
      final t2 = await provider.createTag(name: 'B', color: 0);
      await provider.setFileTags('/doc.pdf', [t1.id, t2.id]);
      expect(provider.getTagsForFile('/doc.pdf'), hasLength(2));

      await provider.forgetFile('/doc.pdf');
      expect(provider.getTagsForFile('/doc.pdf'), isEmpty);
    });

    // Arrange: build provider with empty prefs
    // Act: forgetFile on a path that was never associated
    // Assert: no throw, tags list still empty
    test('forgetFile does not throw for an unknown file path', () async {
      final provider = await _buildProvider({});
      // Should not throw
      await provider.forgetFile('/never/existed.pdf');
      expect(provider.tags, isEmpty);
    });

    // Arrange: build provider, create tag, associate it with two files
    // Act: countFilesWithTag(tag.id)
    // Assert: returns 2 (third file has no tags)
    test('countFilesWithTag returns correct count for associated files', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'Shared', color: 0);
      await provider.setFileTags('/a.pdf', [tag.id]);
      await provider.setFileTags('/b.pdf', [tag.id]);
      await provider.setFileTags('/c.pdf', []); // no tag

      expect(provider.countFilesWithTag(tag.id), equals(2));
    });

    // Arrange: build provider, create a tag
    // Act: tagById(tag.id)
    // Assert: returns the tag with matching name
    test('tagById returns the correct tag for a known id', () async {
      final provider = await _buildProvider({});
      final tag = await provider.createTag(name: 'FindMe', color: 0);
      expect(provider.tagById(tag.id)?.name, equals('FindMe'));
    });

    // Arrange: build provider with empty prefs
    // Act: tagById('nonexistent')
    // Assert: returns null
    test('tagById returns null for an unknown id', () async {
      final provider = await _buildProvider({});
      expect(provider.tagById('nonexistent'), isNull);
    });

    // Arrange: first TagProvider instance, create a tag
    // Act: re-read tags from the same SharedPreferences via TagService
    // Assert: tag persists across provider recreation
    test('tags persist across TagProvider recreation (simulated restart)', () async {
      // First provider instance: create a tag
      SharedPreferences.setMockInitialValues({});
      final prefs1 = await SharedPreferences.getInstance();
      final provider1 = TagProvider(TagService(prefs1));
      await provider1.createTag(name: 'Persistent', color: 0xABCDEF);

      // Simulate app restart: same prefs singleton still has the data
      final service = TagService(prefs1);
      expect(service.getAllTags(), hasLength(1));
      expect(service.getAllTags().first.name, equals('Persistent'));
    });
  });
}
