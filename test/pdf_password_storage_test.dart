// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freya_pdf/features/security/pdf_password_storage.dart';

class _MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  _MockSecureStorage() : super();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  group('PdfPasswordStorage', () {
    late _MockSecureStorage mockStorage;
    late PdfPasswordStorage storage;

    setUp(() {
      mockStorage = _MockSecureStorage();
      storage = PdfPasswordStorage(storage: mockStorage);
    });

    test('reads and overwrites a password for the same file', () async {
      await storage.write('/docs/statement.pdf', 'first');
      expect(await storage.read('/docs/statement.pdf'), 'first');

      await storage.write('/docs/statement.pdf', 'second');
      expect(await storage.read('/docs/statement.pdf'), 'second');
    });

    test('keeps passwords for different files separate', () async {
      await storage.write('/docs/a.pdf', 'a-pass');
      await storage.write('/docs/b.pdf', 'b-pass');

      expect(await storage.read('/docs/a.pdf'), 'a-pass');
      expect(await storage.read('/docs/b.pdf'), 'b-pass');
    });

    test('deletes one password without touching another', () async {
      await storage.write('/docs/a.pdf', 'a-pass');
      await storage.write('/docs/b.pdf', 'b-pass');

      await storage.delete('/docs/a.pdf');

      expect(await storage.read('/docs/a.pdf'), isNull);
      expect(await storage.read('/docs/b.pdf'), 'b-pass');
    });

    test('clearAll removes only remembered PDF passwords', () async {
      await storage.write('/docs/a.pdf', 'a-pass');
      await storage.write('/docs/b.pdf', 'b-pass');
      await mockStorage.write(key: 'other-secret', value: 'keep-me');

      await storage.clearAll();

      expect(await storage.read('/docs/a.pdf'), isNull);
      expect(await storage.read('/docs/b.pdf'), isNull);
      expect(mockStorage.values['other-secret'], 'keep-me');
    });
  });
}
