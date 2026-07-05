// Size: small — service tests backed by mock SharedPreferences (no real I/O, milliseconds)

import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/features/settings/user_profile.dart';
import 'package:feya_pdf/features/settings/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsService', () {
    // Seed an empty mock once; getInstance() returns the same singleton.
    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
    });

    late SharedPreferences prefs;
    late SettingsService service;

    setUp(() async {
      prefs = await SharedPreferences.getInstance();
      // Clear all keys between tests by removing them individually
      if (prefs.getKeys().isNotEmpty) {
        // Remove everything to start fresh
        for (final key in prefs.getKeys().toList()) {
          await prefs.remove(key);
        }
      }
      service = SettingsService(prefs);
    });

    // --- Theme ---
    // Arrange: mock SharedPreferences with no initial values
    // Act: read themeMode from freshly constructed SettingsService
    // Assert: defaults to 'system'
    test('themeMode defaults to system when not set', () {
      expect(service.themeMode, equals('system'));
    });

    // Arrange: fresh SettingsService (prefs cleared in setUp)
    // Act: call setThemeMode('dark') and read back themeMode
    // Assert: themeMode equals 'dark'
    test('setThemeMode persists and returns the set value', () async {
      await service.setThemeMode('dark');
      expect(service.themeMode, equals('dark'));
    });

    // Arrange: fresh SettingsService
    // Act: setThemeMode('light') then setThemeMode('dark')
    // Assert: second set wins, themeMode equals 'dark'
    test('setThemeMode can be read back after multiple sets', () async {
      await service.setThemeMode('light');
      expect(service.themeMode, equals('light'));
      await service.setThemeMode('dark');
      expect(service.themeMode, equals('dark'));
    });

    // --- Auto-encrypt ---
    // Arrange: fresh SettingsService
    // Act: read autoEncrypt before setting
    // Assert: defaults to false
    test('autoEncrypt defaults to false when not set', () {
      expect(service.autoEncrypt, isFalse);
    });

    // Arrange: fresh SettingsService
    // Act: setAutoEncrypt(true) and read back
    // Assert: autoEncrypt is true
    test('setAutoEncrypt true persists', () async {
      await service.setAutoEncrypt(true);
      expect(service.autoEncrypt, isTrue);
    });

    // Arrange: fresh SettingsService
    // Act: setAutoEncrypt(true) then setAutoEncrypt(false)
    // Assert: autoEncrypt is false
    test('setAutoEncrypt false persists', () async {
      await service.setAutoEncrypt(true);
      await service.setAutoEncrypt(false);
      expect(service.autoEncrypt, isFalse);
    });

    // --- User profile ---
    // Arrange: fresh SettingsService (no profile stored)
    // Act: read userProfile
    // Assert: equals default UserProfile()
    test('userProfile returns default when not set', () {
      expect(service.userProfile, equals(const UserProfile()));
    });

    // Arrange: fresh SettingsService
    // Act: setUserProfile(name:'Max', email:'max@example.com') and read back
    // Assert: name and email match
    test('setUserProfile persists and returns correct values', () async {
      final profile = UserProfile(name: 'Max', email: 'max@example.com');
      await service.setUserProfile(profile);
      expect(service.userProfile.name, equals('Max'));
      expect(service.userProfile.email, equals('max@example.com'));
    });

    // Arrange: fresh SettingsService
    // Act: setUserProfile with null avatarPath, read back
    // Assert: name and email correct, avatarPath is null
    test('setUserProfile with null avatarPath stores null avatarPath', () async {
      final profile = const UserProfile(name: 'Alice', email: 'alice@test.com');
      await service.setUserProfile(profile);
      final loaded = service.userProfile;
      expect(loaded.name, equals('Alice'));
      expect(loaded.avatarPath, isNull);
    });

    // --- Last read page ---
    // Arrange: fresh SettingsService
    // Act: read lastReadPositions before any sets
    // Assert: empty map
    test('lastReadPositions defaults to empty map', () {
      expect(service.lastReadPositions, isEmpty);
    });

    // Arrange: fresh SettingsService
    // Act: setLastReadPage('/path/to/file.pdf', 42) then getLastReadPage
    // Assert: returns 42
    test('setLastReadPage persists and getLastReadPage retrieves it', () async {
      await service.setLastReadPage('/path/to/file.pdf', 42, 100);
      expect(service.getLastReadPage('/path/to/file.pdf'), equals(42));
    });

    // Arrange: fresh SettingsService
    // Act: setLastReadPage('/path/a.pdf', 10) then setLastReadPage('/path/a.pdf', 25)
    // Assert: getLastReadPage returns 25 (updated value)
    test('setLastReadPage updates existing entry', () async {
      await service.setLastReadPage('/path/a.pdf', 10, 100);
      await service.setLastReadPage('/path/a.pdf', 25, 100);
      expect(service.getLastReadPage('/path/a.pdf'), equals(25));
    });

    // Arrange: fresh SettingsService
    // Act: setLastReadPage for three different file paths
    // Assert: each path returns its own stored page number
    test('setLastReadPage handles multiple files independently', () async {
      await service.setLastReadPage('/a.pdf', 5, 100);
      await service.setLastReadPage('/b.pdf', 15, 200);
      await service.setLastReadPage('/c.pdf', 99, 300);
      expect(service.getLastReadPage('/a.pdf'), equals(5));
      expect(service.getLastReadPage('/b.pdf'), equals(15));
      expect(service.getLastReadPage('/c.pdf'), equals(99));
    });

    // Arrange: fresh SettingsService with no entries
    // Act: getLastReadPage for unknown path
    // Assert: returns null
    test('getLastReadPage returns null for unknown file path', () {
      expect(service.getLastReadPage('/unknown.pdf'), isNull);
    });

    // --- Legacy migration ---
    // Arrange: mock prefs with legacy 'last_dir' key set
    // Act: call migrateLegacyKeys() then read new key
    // Assert: new key 'mely_pdf_last_dir' has the migrated value
    test('migrateLegacyKeys copies old last_dir key to new key', () async {
      await prefs.setString('last_dir', '/legacy/path');
      await service.migrateLegacyKeys();
      expect(prefs.getString('mely_pdf_last_dir'), equals('/legacy/path'));
    });

    // Arrange: mock prefs with both old 'last_dir' and new 'mely_pdf_last_dir' set
    // Act: call migrateLegacyKeys()
    // Assert: new key is not overwritten by old value
    test('migrateLegacyKeys does not overwrite existing new key', () async {
      await prefs.setString('last_dir', '/old/path');
      await prefs.setString('mely_pdf_last_dir', '/new/path');
      await service.migrateLegacyKeys();
      expect(prefs.getString('mely_pdf_last_dir'), equals('/new/path'));
    });

    // Arrange: mock prefs with only new key set, no old key
    // Act: call migrateLegacyKeys()
    // Assert: new key unchanged
    test('migrateLegacyKeys does nothing when old key is absent', () async {
      await prefs.setString('mely_pdf_last_dir', '/already/set');
      await service.migrateLegacyKeys();
      expect(prefs.getString('mely_pdf_last_dir'), equals('/already/set'));
    });

    // --- Combined operations ---
    // Arrange: fresh SettingsService
    // Act: set themeMode, autoEncrypt, and lastReadPage independently
    // Assert: all three values read back correctly without interfering
    test('multiple settings can be set and read independently', () async {
      await service.setThemeMode('dark');
      await service.setAutoEncrypt(true);
      await service.setLastReadPage('/doc.pdf', 7, 100);

      expect(service.themeMode, equals('dark'));
      expect(service.autoEncrypt, isTrue);
      expect(service.getLastReadPage('/doc.pdf'), equals(7));
    });
  });
}
