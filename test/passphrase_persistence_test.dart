// Copyright (c) 2026 Freya. All rights reserved.
//
// Regression tests for the passphrase-persistence bugfix: the secure-folder
// passphrase was previously held only in memory and forgotten on every app
// restart. These tests verify:
//   (a) setting a passphrase via showPassphraseDialog persists it to the
//       Keystore-backed secure storage,
//   (b) the restored-passphrase path (EncryptionProvider initialPassphrase)
//       rehydrates state on startup,
//   (c) clearing the passphrase also clears the persisted copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/encryption/widgets/passphrase_dialog.dart';
import 'package:freya_pdf/features/security/biometric_passphrase_storage.dart';

/// In-memory [FlutterSecureStoragePlatform] so the real [FlutterSecureStorage]
/// used internally by `showPassphraseDialog` can resolve on the test host.
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
    // BiometricPassphraseStorage.read() runs a one-time migration that calls
    // SharedPreferences.getInstance(); mock it so the fake-async test
    // environment doesn't hang on a real platform channel.
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();
  });

  tearDown(() async {
    final platform = FlutterSecureStoragePlatform.instance;
    await platform.deleteAll(options: const <String, String>{});
  });

  group('BUG 1a — setPassphrase persists via dialog', () {
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

        // Type a valid (>=8 chars, non-common) passphrase and confirm.
        await tester.enterText(find.byType(TextField), 'correct horse battery');
        await tester.pump();
        await tester.tap(find.text('Set'));
        // Let the dialog pop (bounded pumps; the passphrase dialog disposes its
        // controller synchronously on pop, so avoid pumpAndSettle here).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // The passphrase must now be persisted to the secure store.
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

  group('BUG 1b — restore-on-startup', () {
    test('EncryptionProvider rehydrates from initialPassphrase', () {
      final provider = EncryptionProvider(initialPassphrase: 'restored-key');
      expect(provider.hasPassphrase, isTrue);
      expect(provider.isLocked, isFalse);
      expect(provider.passphrase, equals('restored-key'));
    });

    test('EncryptionProvider with a null initialPassphrase starts locked', () {
      final provider = EncryptionProvider(initialPassphrase: null);
      expect(provider.hasPassphrase, isFalse);
      expect(provider.isLocked, isTrue);
    });

    test('EncryptionProvider with an empty initialPassphrase starts locked',
        () {
      final provider = EncryptionProvider(initialPassphrase: '');
      expect(provider.hasPassphrase, isFalse);
      expect(provider.isLocked, isTrue);
    });

    test('stored passphrase round-trips through the storage → provider path',
        () async {
      final storage = BiometricPassphraseStorage();
      await storage.write('round-trip-passphrase');

      // This mirrors the restore wiring in main.dart: read once, then hand the
      // value (if non-empty) into the provider before runApp.
      final stored = await storage.read();
      final provider = EncryptionProvider(
        initialPassphrase:
            (stored != null && stored.isNotEmpty) ? stored : null,
      );

      expect(provider.passphrase, equals('round-trip-passphrase'));
      expect(provider.hasPassphrase, isTrue);
    });

    test('no stored value → provider starts unlocked false (no re-prompt data)',
        () async {
      final storage = BiometricPassphraseStorage();
      final stored = await storage.read();
      final provider = EncryptionProvider(
        initialPassphrase:
            (stored != null && stored.isNotEmpty) ? stored : null,
      );
      expect(provider.hasPassphrase, isFalse);
    });
  });

  group('BUG 1c — clearPassphrase clears the persisted copy', () {
    test('clearPassphrase empties the secure store', () async {
      final storage = BiometricPassphraseStorage();
      final provider = EncryptionProvider(initialPassphrase: 'to-be-cleared');
      await storage.write('to-be-cleared');

      expect(await storage.read(), equals('to-be-cleared'));

      await provider.clearPassphrase();

      expect(provider.hasPassphrase, isFalse);
      expect(await storage.read(), isNull,
          reason: 'clearing the passphrase must also clear the persisted copy');
    });
  });
}
