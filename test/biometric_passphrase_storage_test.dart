// Unit tests for BiometricPassphraseStorage.
//
// Verifies that the secure-storage-based class behaves correctly and
// performs a one-time migration from the legacy SharedPreferences key.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freya_pdf/features/security/biometric_passphrase_storage.dart';

// ── Mock FlutterSecureStorage ──
// Extends the real class to satisfy the type check.
class MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  MockSecureStorage() : super();

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    _store[key] = value ?? '';
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
  }) async {
    _store.remove(key);
  }
}

void main() {
  group('BiometricPassphraseStorage', () {
    late MockSecureStorage mockStorage;
    late BiometricPassphraseStorage storage;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      mockStorage = MockSecureStorage();
      storage = BiometricPassphraseStorage(storage: mockStorage);
    });

    test('returns null when nothing is stored', () async {
      expect(await storage.read(), isNull);
    });

    test('write then read returns the same passphrase', () async {
      await storage.write('correct horse battery staple');
      expect(await storage.read(), equals('correct horse battery staple'));
    });

    test('write overwrites previous value', () async {
      await storage.write('first');
      await storage.write('second');
      expect(await storage.read(), equals('second'));
    });

    test('clear removes stored passphrase', () async {
      await storage.write('hello');
      expect(await storage.read(), equals('hello'));
      await storage.clear();
      expect(await storage.read(), isNull);
    });

    test('clearing an empty store is a no-op', () async {
      await storage.clear();
      expect(await storage.read(), isNull);
    });

    test(
      'one-time migration: copies legacy SharedPreferences value into '
      'secure storage and erases the plaintext copy',
      () async {
        // Seed legacy plaintext entry.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('_freya_bio_passphrase', 'old-shared-prefs');

        // First read triggers migration.
        final value = await storage.read();
        expect(value, equals('old-shared-prefs'));

        // Legacy entry should be gone.
        expect(prefs.getString('_freya_bio_passphrase'), isNull);

        // And the value should be in the secure store now.
        expect(mockStorage._store['_freya_bio_passphrase'],
            equals('old-shared-prefs'));
      },
    );

    test(
      'migration is idempotent: re-running with no legacy entry is a no-op',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('_freya_bio_passphrase', 'something');
        // First read migrates + clears legacy.
        await storage.read();
        // No legacy entry anymore — second read does nothing special.
        final again = await storage.read();
        expect(again, equals('something'));
        expect(prefs.getString('_freya_bio_passphrase'), isNull);
      },
    );

    test(
      'migration preserves an existing secure-storage entry over legacy',
      () async {
        // Legacy entry from an older install.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('_freya_bio_passphrase', 'legacy');

        // But secure storage already holds a *different* (newer) value.
        await storage.write('secure');

        await storage.read();

        // Secure value wins; legacy entry is cleared regardless.
        expect(await storage.read(), equals('secure'));
        expect(prefs.getString('_freya_bio_passphrase'), isNull);
      },
    );
  });
}
