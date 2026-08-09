import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';

void main() {
  group('SettingsService — reading progress', () {
    late SharedPreferences prefs;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs);
    });

    test('getLastReadPage returns null when nothing stored', () {
      expect(service.getLastReadPage('/test.pdf'), isNull);
    });

    test('getLastReadProgress returns null when nothing stored', () {
      expect(service.getLastReadProgress('/test.pdf'), isNull);
    });

    test('setLastReadPage and getLastReadPage round-trips', () async {
      await service.setLastReadPage('/test.pdf', 5, 0);

      expect(service.getLastReadPage('/test.pdf'), 5);
    });

    test('setLastReadPage and getLastReadProgress round-trips', () async {
      await service.setLastReadPage('/test.pdf', 3, 10);

      final progress = service.getLastReadProgress('/test.pdf');
      expect(progress, isNotNull);
      expect(progress!.page, 3);
      expect(progress.totalPages, 10);
    });

    test('multiple files stored independently', () async {
      await service.setLastReadPage('/a.pdf', 5, 10);
      await service.setLastReadPage('/b.pdf', 12, 20);

      expect(service.getLastReadPage('/a.pdf'), 5);
      expect(service.getLastReadPage('/b.pdf'), 12);

      final aProgress = service.getLastReadProgress('/a.pdf');
      expect(aProgress!.page, 5);
      expect(aProgress.totalPages, 10);

      final bProgress = service.getLastReadProgress('/b.pdf');
      expect(bProgress!.page, 12);
      expect(bProgress.totalPages, 20);
    });

    test('subsequent calls overwrite previous value', () async {
      await service.setLastReadPage('/test.pdf', 3, 10);
      await service.setLastReadPage('/test.pdf', 7, 15);

      final progress = service.getLastReadProgress('/test.pdf');
      expect(progress!.page, 7);
      expect(progress.totalPages, 15);
    });

    test('getLastReadPage returns null after overwrite with different page', () async {
      await service.setLastReadPage('/test.pdf', 1, 5);
      await service.setLastReadPage('/other.pdf', 2, 5);

      // /test.pdf still has its value
      expect(service.getLastReadPage('/test.pdf'), 1);
    });
  });

  group('SettingsProvider — reading progress', () {
    late SharedPreferences prefs;
    late SettingsService service;
    late SettingsProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs);
      provider = SettingsProvider(service);
    });

    test('getLastReadPage returns null when nothing stored', () {
      expect(provider.getLastReadPage('/test.pdf'), isNull);
    });

    test('getLastReadProgress returns null when nothing stored', () {
      expect(provider.getLastReadProgress('/test.pdf'), isNull);
    });

    test('setLastReadPage persists and getLastReadPage retrieves', () async {
      await provider.setLastReadPage('/test.pdf', 7);

      expect(provider.getLastReadPage('/test.pdf'), 7);
    });

    test('setLastReadPage with totalPages persists progress', () async {
      await provider.setLastReadPage('/test.pdf', 3, totalPages: 10);

      final progress = provider.getLastReadProgress('/test.pdf');
      expect(progress, isNotNull);
      expect(progress!.page, 3);
      expect(progress.totalPages, 10);
    });

    test('setLastReadPage with totalPages stores page and total', () async {
      await provider.setLastReadPage('/test.pdf', 5, totalPages: 20);

      final progress = provider.getLastReadProgress('/test.pdf');
      expect(progress, isNotNull);
      expect(progress!.page, 5);
      expect(progress.totalPages, 20);

      expect(provider.getLastReadPage('/test.pdf'), 5);
    });

    test('different files tracked independently', () async {
      await provider.setLastReadPage('/a.pdf', 2, totalPages: 5);
      await provider.setLastReadPage('/b.pdf', 8, totalPages: 10);

      expect(provider.getLastReadPage('/a.pdf'), 2);
      expect(provider.getLastReadPage('/b.pdf'), 8);

      final aProgress = provider.getLastReadProgress('/a.pdf');
      expect(aProgress!.page, 2);
      expect(aProgress.totalPages, 5);

      final bProgress = provider.getLastReadProgress('/b.pdf');
      expect(bProgress!.page, 8);
      expect(bProgress.totalPages, 10);
    });

    test('updating existing file changes progress', () async {
      await provider.setLastReadPage('/test.pdf', 1, totalPages: 10);
      await provider.setLastReadPage('/test.pdf', 9, totalPages: 10);

      expect(provider.getLastReadPage('/test.pdf'), 9);
      expect(provider.getLastReadProgress('/test.pdf')!.page, 9);
    });
  });
}
