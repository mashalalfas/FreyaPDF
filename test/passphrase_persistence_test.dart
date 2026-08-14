// Copyright (c) 2026 Freya. All rights reserved.
//
// Regression tests for passphrase persistence and gated restore:
//   (a) setting a passphrase via showPassphraseDialog persists it to the
//       Keystore-backed secure storage,
//   (b) EncryptionProvider starts locked (no auto-restore at startup),
//   (c) the stored passphrase is released into EncryptionProvider only AFTER
//       successful app-lock authentication (biometric or PIN),
//   (d) when app lock is disabled, the passphrase is NOT auto-restored —
//       the user must enter it when opening encrypted content,
//   (e) clearing the passphrase also clears the persisted copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/encryption/widgets/passphrase_dialog.dart';
import 'package:freya_pdf/features/security/biometric_passphrase_storage.dart';
import 'package:freya_pdf/features/security/widgets/app_lock_screen.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';

/// In-memory [FlutterSecureStoragePlatform] so the real [FlutterSecureStorage]
/// used internally by `BiometricPassphraseStorage` can resolve on the test host.
class MockSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final _store = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return _store[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _store.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.unmodifiable(_store);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _store.clear();
  }

  String? peek(String key) => _store[key];
}

/// Mock local-auth platform that always succeeds authentication.
class SuccessLocalAuthPlatform extends LocalAuthPlatform
    with MockPlatformInterfaceMixin {
  int authenticateCallCount = 0;

  @override
  Future<bool> deviceSupportsBiometrics() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async =>
      [BiometricType.fingerprint];

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authenticateCallCount++;
    return true;
  }
}

Widget _wrapWithEncryption(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<EncryptionProvider>(
        create: (_) => EncryptionProvider(),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();
  });

  tearDown(() async {
    final platform = FlutterSecureStoragePlatform.instance;
    await platform.deleteAll(options: const <String, String>{});
  });

  group('Passphrase persistence via dialog', () {
    testWidgets(
      'entering a passphrase in showPassphraseDialog writes it to secure '
      'storage',
      (tester) async {
        final storage = BiometricPassphraseStorage();

        await tester.pumpWidget(
          _wrapWithEncryption(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showPassphraseDialog(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'correct horse battery');
        await tester.pump();
        await tester.tap(find.text('Set'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          await storage.read(),
          equals('correct horse battery'),
          reason: 'showPassphraseDialog must persist the passphrase so it '
              'survives an app restart',
        );
      },
    );

    testWidgets(
      'the persisted value is reflected in the EncryptionProvider state',
      (tester) async {
        EncryptionProvider? provider;
        final storage = BiometricPassphraseStorage();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<EncryptionProvider>(
                create: (_) => EncryptionProvider(),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  provider = context.read<EncryptionProvider>();
                  return Scaffold(
                    body: Center(
                      child: Builder(
                        builder: (context) => TextButton(
                          onPressed: () => showPassphraseDialog(context),
                          child: const Text('open'),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField), 'another secret key');
        await tester.pump();
        await tester.tap(find.text('Set'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(provider!.hasPassphrase, isTrue);
        expect(provider!.passphrase, equals('another secret key'));
        expect(await storage.read(), equals('another secret key'));
      },
    );
  });

  group('EncryptionProvider starts locked (no auto-restore)', () {
    test('EncryptionProvider with default constructor starts locked', () {
      final provider = EncryptionProvider();
      expect(provider.hasPassphrase, isFalse);
      expect(provider.isLocked, isTrue);
      expect(provider.passphrase, isNull);
    });

    test('stored passphrase is NOT loaded into provider at construction',
        () async {
      final storage = BiometricPassphraseStorage();
      await storage.write('secret-passphrase');

      // Even though a passphrase is stored, the provider starts locked.
      // The passphrase will only be released after app-lock authentication.
      final provider = EncryptionProvider();
      expect(provider.hasPassphrase, isFalse);
      expect(provider.isLocked, isTrue);
    });
  });

  group('Passphrase restore gated behind app-lock authentication', () {
    testWidgets(
      'AppLockGate restores passphrase after successful biometric unlock',
      (tester) async {
        final platform = SuccessLocalAuthPlatform();
        LocalAuthPlatform.instance = platform;
        FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsProvider(SettingsService(prefs));
        await settings.setAppLockEnabled(true);

        // Pre-store a passphrase that should be restored after unlock.
        final storage = BiometricPassphraseStorage();
        await storage.write('gated-passphrase');

        EncryptionProvider? encryptionProvider;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<EncryptionProvider>(
                create: (_) => EncryptionProvider(),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  encryptionProvider = context.read<EncryptionProvider>();
                  return AppLockGate(child: const SizedBox.shrink());
                },
              ),
            ),
          ),
        );

        // Provider starts locked (no auto-restore).
        expect(encryptionProvider!.hasPassphrase, isFalse);

        // Let _checkLock run and fire biometric prompt.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // After successful biometric auth, passphrase should be restored.
        expect(platform.authenticateCallCount, greaterThanOrEqualTo(1));
        expect(encryptionProvider!.hasPassphrase, isTrue);
        expect(encryptionProvider!.passphrase, equals('gated-passphrase'));
      },
    );

    testWidgets(
      'AppLockGate does NOT restore passphrase when app lock is disabled',
      (tester) async {
        FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsProvider(SettingsService(prefs));
        await settings.setAppLockEnabled(false);

        // Pre-store a passphrase.
        final storage = BiometricPassphraseStorage();
        await storage.write('should-not-restore');

        EncryptionProvider? encryptionProvider;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<EncryptionProvider>(
                create: (_) => EncryptionProvider(),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  encryptionProvider = context.read<EncryptionProvider>();
                  return AppLockGate(child: const SizedBox.shrink());
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // When app lock is disabled, the gate opens immediately but does NOT
        // restore the passphrase. The user must enter it when accessing
        // encrypted content.
        expect(encryptionProvider!.hasPassphrase, isFalse);
      },
    );

    testWidgets(
      'AppLockGate does not overwrite existing passphrase on unlock',
      (tester) async {
        final platform = SuccessLocalAuthPlatform();
        LocalAuthPlatform.instance = platform;
        FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsProvider(SettingsService(prefs));
        await settings.setAppLockEnabled(true);

        // Pre-store a passphrase.
        final storage = BiometricPassphraseStorage();
        await storage.write('stored-passphrase');

        // Provider already has a passphrase set (e.g., from a previous session
        // or manual entry).
        final existingProvider = EncryptionProvider();
        existingProvider.setPassphrase('existing-passphrase');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
              ChangeNotifierProvider<EncryptionProvider>.value(
                  value: existingProvider),
            ],
            child: MaterialApp(
              home: AppLockGate(child: const SizedBox.shrink()),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Existing passphrase should not be overwritten.
        expect(existingProvider.passphrase, equals('existing-passphrase'));
      },
    );
  });

  group('clearPassphrase clears the persisted copy', () {
    test('clearPassphrase empties the secure store', () async {
      final storage = BiometricPassphraseStorage();
      final provider = EncryptionProvider();
      provider.setPassphrase('to-be-cleared');
      await storage.write('to-be-cleared');

      expect(await storage.read(), equals('to-be-cleared'));

      await provider.clearPassphrase();

      expect(provider.hasPassphrase, isFalse);
      expect(await storage.read(), isNull,
          reason: 'clearing the passphrase must also clear the persisted copy');
    });
  });
}
