// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/digests/sha256.dart';

import 'package:freya_pdf/features/security/app_lock_service.dart';

// ── Mock FlutterSecureStorage ──
// Same shape as the existing app_lock_test.dart; we duplicate it here so
// this test file stands alone and can be run in isolation against the
// new PBKDF2 + migration code paths.
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

  /// Test-only peek at the raw stored value (bypasses public API).
  String? peek(String key) => _store[key];
}

/// Compute the legacy v1 hash: single-round SHA-256 over `<salt>:<pin>`,
/// base64-encoded. Mirrors the algorithm that older versions of
/// AppLockService used, so the migration tests can seed a believable
/// legacy entry without poking into production internals.
String _legacyHash(String saltB64, String pin) {
  final digest = SHA256Digest().process(
    Uint8List.fromList(utf8.encode('$saltB64:$pin')),
  );
  return base64.encode(digest);
}

void main() {
  group('AppLockService PBKDF2 hashing (v2)', () {
    late AppLockService service;
    late MockSecureStorage storage;

    setUp(() {
      storage = MockSecureStorage();
      service = AppLockService(storage: storage);
    });

    test('setPin writes v2 PBKDF2 format', () async {
      await service.setPin('123456');
      final stored = storage.peek('app_lock_pin_hash');
      expect(stored, isNotNull);
      expect(stored, startsWith(r'pbkdf2_sha256$'));
    });

    test('v2 format encodes prefix, iteration count, salt and hash',
        () async {
      await service.setPin('123456');
      final stored = storage.peek('app_lock_pin_hash')!;
      final parts = stored.split(r'$');
      expect(parts, hasLength(4));
      expect(parts[0], equals('pbkdf2_sha256'));
      final iterations = int.tryParse(parts[1]);
      expect(iterations, isNotNull);
      expect(iterations, greaterThanOrEqualTo(100000));
      expect(base64.decode(parts[2]), hasLength(16));
      expect(base64.decode(parts[3]), hasLength(32));
    });

    test('two setPin calls with same PIN produce different stored blobs',
        () async {
      await service.setPin('123456');
      final first = storage.peek('app_lock_pin_hash')!;
      await service.setPin('123456');
      final second = storage.peek('app_lock_pin_hash')!;
      // Random salt must yield a different stored value each time.
      expect(first, isNot(equals(second)));
    });

    test('verifyPin succeeds with correct PIN (v2 path)', () async {
      await service.setPin('987654');
      expect(await service.verifyPin('987654'), isTrue);
    });

    test('verifyPin rejects wrong PIN (v2 path)', () async {
      await service.setPin('987654');
      expect(await service.verifyPin('111111'), isFalse);
    });

    test('verifyPin works with 4-digit PIN', () async {
      await service.setPin('1234');
      expect(await service.verifyPin('1234'), isTrue);
      expect(await service.verifyPin('12345'), isFalse);
    });

    test('verifyPin is length and content sensitive', () async {
      await service.setPin('123456');
      expect(await service.verifyPin('123456 '), isFalse);
      expect(await service.verifyPin('12345'), isFalse);
      expect(await service.verifyPin('1234567'), isFalse);
    });
  });

  group('AppLockService legacy v1 SHA-256 migration', () {
    test('legacy v1 entry is verified and silently migrated to v2',
        () async {
      final storage = MockSecureStorage();
      const pin = '424242';
      const saltB64 = 'AAAAAAAAAAAAAAAAAAAAAA=='; // 16 zero bytes, base64
      final legacy = '$saltB64:${_legacyHash(saltB64, pin)}';
      await storage.write(key: 'app_lock_pin_hash', value: legacy);

      final service = AppLockService(storage: storage);
      expect(await service.verifyPin(pin), isTrue);

      // After successful verify the stored value must be v2.
      final upgraded = storage.peek('app_lock_pin_hash')!;
      expect(upgraded, startsWith(r'pbkdf2_sha256$'));
      expect(upgraded, isNot(equals(legacy)));
      // And the new entry must still verify the same PIN.
      expect(await service.verifyPin(pin), isTrue);
    });

    test('legacy v1 entry with wrong PIN is rejected, not migrated',
        () async {
      final storage = MockSecureStorage();
      const pin = '424242';
      const saltB64 = 'AAAAAAAAAAAAAAAAAAAAAA==';
      final legacy = '$saltB64:${_legacyHash(saltB64, pin)}';
      await storage.write(key: 'app_lock_pin_hash', value: legacy);

      final service = AppLockService(storage: storage);
      expect(await service.verifyPin('999999'), isFalse);

      // Entry must remain in legacy form — no spurious migration.
      final after = storage.peek('app_lock_pin_hash')!;
      expect(after, isNot(startsWith(r'pbkdf2_sha256$')));
      expect(after, equals(legacy));
    });

    test('malformed legacy entry is rejected', () async {
      final storage = MockSecureStorage();
      await storage.write(key: 'app_lock_pin_hash', value: 'no-colon-here');
      final service = AppLockService(storage: storage);
      expect(await service.verifyPin('1234'), isFalse);
    });

    test('v2 entry with non-positive iteration count is rejected',
        () async {
      final storage = MockSecureStorage();
      await storage.write(
        key: 'app_lock_pin_hash',
        value:
            'pbkdf2_sha256\$-1\${base64.encode([1, 2, 3, 4])}\${base64.encode([5, 6, 7, 8])}',
      );
      final service = AppLockService(storage: storage);
      expect(await service.verifyPin('1234'), isFalse);
    });

    test('v2 entry with bad base64 is rejected', () async {
      final storage = MockSecureStorage();
      await storage.write(
        key: 'app_lock_pin_hash',
        value: r'pbkdf2_sha256$100000$!!!notbase64$!!!notbase64',
      );
      final service = AppLockService(storage: storage);
      expect(await service.verifyPin('1234'), isFalse);
    });

    test('v2 entry with wrong segment count is rejected', () async {
      final storage = MockSecureStorage();
      await storage.write(
        key: 'app_lock_pin_hash',
        value: r'pbkdf2_sha256$100000',
      );
      final service = AppLockService(storage: storage);
      expect(await service.verifyPin('1234'), isFalse);
    });

    test('v2 entry with wrong prefix is treated as legacy and rejected',
        () async {
      final storage = MockSecureStorage();
      await storage.write(
        key: 'app_lock_pin_hash',
        value: 'argon2\$100000\$AAAA\${base64.encode([5, 6, 7, 8])}',
      );
      final service = AppLockService(storage: storage);
      // Wrong prefix → fallback to v1 parser → no colon → reject.
      expect(await service.verifyPin('1234'), isFalse);
    });
  });
}
