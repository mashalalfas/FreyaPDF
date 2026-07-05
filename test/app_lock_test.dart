import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feya_pdf/features/security/app_lock_service.dart';
import 'package:feya_pdf/features/settings/settings_service.dart';
import 'package:feya_pdf/features/settings/settings_provider.dart';

// ── Mock FlutterSecureStorage ──
// Extends the real class to pass the type check.
class MockSecureStorage extends FlutterSecureStorage {
  final _store = <String, String>{};

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
  group('AppLockService (PIN only)', () {
    late AppLockService service;

    setUp(() {
      service = AppLockService(storage: MockSecureStorage());
    });

    test('setPin and verifyPin match', () async {
      await service.setPin('123456');
      expect(await service.verifyPin('123456'), isTrue);
    });

    test('verifyPin rejects wrong PIN', () async {
      await service.setPin('123456');
      expect(await service.verifyPin('654321'), isFalse);
    });

    test('hasPin returns false before set, true after', () async {
      expect(await service.hasPin(), isFalse);
      await service.setPin('111111');
      expect(await service.hasPin(), isTrue);
    });

    test('clearPin removes stored hash', () async {
      await service.setPin('123456');
      expect(await service.hasPin(), isTrue);
      await service.clearPin();
      expect(await service.hasPin(), isFalse);
    });

    test('verifyPin fails on cleared pin', () async {
      await service.setPin('123456');
      await service.clearPin();
      expect(await service.verifyPin('123456'), isFalse);
    });

    test('setPin overwrites previous pin', () async {
      await service.setPin('111111');
      await service.setPin('222222');
      expect(await service.verifyPin('111111'), isFalse);
      expect(await service.verifyPin('222222'), isTrue);
    });

    test('works with 4-digit PIN', () async {
      await service.setPin('1234');
      expect(await service.verifyPin('1234'), isTrue);
      expect(await service.verifyPin('12345'), isFalse);
    });

    test('works with 6-digit PIN', () async {
      await service.setPin('987654');
      expect(await service.verifyPin('987654'), isTrue);
    });

    test('biometricEnabled defaults to false', () async {
      expect(await service.getBiometricEnabled(), isFalse);
    });

    test('setBiometricEnabled round-trips', () async {
      await service.setBiometricEnabled(true);
      expect(await service.getBiometricEnabled(), isTrue);
      await service.setBiometricEnabled(false);
      expect(await service.getBiometricEnabled(), isFalse);
    });

    test('clearPin also clears biometric flag', () async {
      await service.setPin('123456');
      await service.setBiometricEnabled(true);
      await service.clearPin();
      expect(await service.getBiometricEnabled(), isFalse);
    });

    test('isBiometricAvailable returns false when no local auth provided',
        () async {
      // Without a LocalAuthentication instance, this should return false
      expect(await service.isBiometricAvailable(), isFalse);
    });
  });

  group('SettingsProvider appLockEnabled', () {
    late SettingsProvider provider;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs);
      provider = SettingsProvider(service);
    });

    test('appLockEnabled defaults to false', () {
      expect(provider.appLockEnabled, isFalse);
    });

    test('setAppLockEnabled updates state', () async {
      await provider.setAppLockEnabled(true);
      expect(provider.appLockEnabled, isTrue);

      await provider.setAppLockEnabled(false);
      expect(provider.appLockEnabled, isFalse);
    });

    test('setAppLockEnabled persists via reload', () async {
      await provider.setAppLockEnabled(true);
      await provider.reload();
      expect(provider.appLockEnabled, isTrue);
    });
  });

  group('SettingsService appLockEnabled', () {
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs);
    });

    test('defaults to false', () {
      expect(service.appLockEnabled, isFalse);
    });

    test('setAppLockEnabled round-trips', () async {
      await service.setAppLockEnabled(true);
      expect(service.appLockEnabled, isTrue);
      await service.setAppLockEnabled(false);
      expect(service.appLockEnabled, isFalse);
    });
  });
}
