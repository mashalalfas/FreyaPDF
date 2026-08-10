// Copyright (c) 2026 Freya. All rights reserved.
//
// Tests for the security fixes reported from real-device testing:
//   BUG 1  — stored PIN length + legacy manual-submit path
//   BUG 2  — async PBKDF2 (v2 format unchanged)
//   BUG 3  — lifecycle-aware re-lock (ignore notification-shade inactive cycles)
//   BUG 4  — USE_BIOMETRIC permission + graceful biometric failure
//
// Pure decision helpers that back the widget logic are exported top-level from
// app_lock_screen.dart so they can be unit-tested here in isolation.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freya_pdf/features/security/app_lock_service.dart';
import 'package:freya_pdf/features/security/widgets/app_lock_screen.dart';

// ── Test doubles ──

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

  String? peek(String key) => _store[key];
}

/// Mock local-auth platform that can be made to throw so we can assert that
/// authenticateWithBiometrics degrades gracefully (returns false, no throw).
class ThrowingLocalAuthPlatform extends LocalAuthPlatform
    with MockPlatformInterfaceMixin {
  final bool throwOnAuthenticate;
  final bool _supported;

  ThrowingLocalAuthPlatform({
    this.throwOnAuthenticate = false,
    bool supported = true,
  }) : _supported = supported;

  @override
  Future<bool> deviceSupportsBiometrics() async => _supported;

  @override
  Future<bool> isDeviceSupported() async => _supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    if (throwOnAuthenticate) {
      throw PlatformException(code: 'not_available', message: 'no sensor');
    }
    return false; // simulate a cancelled/denied prompt
  }
}

void main() {
  SharedPreferences.setMockInitialValues({});

  group('BUG 1 — PIN length helpers', () {
    test('shouldAutoSubmitPin auto-submits exactly at the stored length', () {
      expect(shouldAutoSubmitPin(4, 4), isTrue);
      expect(shouldAutoSubmitPin(6, 6), isTrue);
      expect(shouldAutoSubmitPin(5, 4), isFalse);
      expect(shouldAutoSubmitPin(3, 4), isFalse);
      expect(shouldAutoSubmitPin(4, null), isFalse);
      expect(shouldAutoSubmitPin(6, null), isFalse);
    });

    test(
        'service: setPin stores length; verify works at stored length',
        () async {
      final storage = MockSecureStorage();
      final service = AppLockService(storage: storage);
      await service.setPin('2401');
      expect(await service.getPinLength(), equals(4));
      expect(await service.verifyPin('2401'), isTrue);
      expect(await service.verifyPin('24010'), isFalse);
      expect(await service.verifyPin('240'), isFalse);
    });

    test(
        'service: legacy install (v2 hash, NO stored length) still verifies '
        'at the actual length', () async {
      final storage = MockSecureStorage();
      final service = AppLockService(storage: storage);
      // A real v2 blob via setPin, then strip the stored length — exactly the
      // broken state of an existing install that set its PIN before this fix.
      await service.setPin('1234');
      await storage.delete(key: 'app_lock_pin_length');
      expect(await service.getPinLength(), isNull);
      // The 4-digit PIN still verifies at length 4 (manual-submit path).
      expect(await service.verifyPin('1234'), isTrue);
      expect(await service.verifyPin('12345'), isFalse);
      expect(await service.verifyPin('123456'), isFalse);
    });

    test(
        'service: legacy install with a 6-digit PIN verifies only at 6',
        () async {
      final storage = MockSecureStorage();
      final service = AppLockService(storage: storage);
      await service.setPin('246810');
      await storage.delete(key: 'app_lock_pin_length');
      expect(await service.getPinLength(), isNull);
      expect(await service.verifyPin('246810'), isTrue);
      expect(await service.verifyPin('24681'), isFalse);
    });
  });

  group('BUG 2 — async PBKDF2 (v2 format unchanged)', () {
    test('setPin completes and produces the v2 pbkdf2 format', () async {
      final storage = MockSecureStorage();
      final service = AppLockService(storage: storage);
      await service.setPin('9876');
      final stored = storage.peek('app_lock_pin_hash')!;
      expect(stored, startsWith(r'pbkdf2_sha256$'));
      final parts = stored.split(r'$');
      expect(parts, hasLength(4));
      expect(parts[0], equals('pbkdf2_sha256'));
      expect(int.parse(parts[1]), greaterThanOrEqualTo(100000));
      expect(await service.verifyPin('9876'), isTrue);
    });
  });

  group('BUG 3 — lifecycle-aware re-lock helpers', () {
    test(
        'notification-shade cycle (inactive -> resumed) does NOT re-lock',
        () {
      // Dragging the shade: the app briefly becomes inactive then resumes.
      // This must not re-trigger the lock screen nor spam biometrics.
      expect(
        shouldRelockOnResume(
            AppLifecycleState.inactive, AppLifecycleState.resumed),
        isFalse,
      );
    });

    test('true background return (paused -> resumed) DOES re-lock', () {
      expect(
        shouldRelockOnResume(
            AppLifecycleState.paused, AppLifecycleState.resumed),
        isTrue,
      );
      expect(
        shouldRelockOnResume(
            AppLifecycleState.hidden, AppLifecycleState.resumed),
        isTrue,
      );
      expect(
        shouldRelockOnResume(
            AppLifecycleState.detached, AppLifecycleState.resumed),
        isTrue,
      );
    });

    test('isBackgroundLifecycleState classifies correctly', () {
      expect(isBackgroundLifecycleState(AppLifecycleState.paused), isTrue);
      expect(isBackgroundLifecycleState(AppLifecycleState.hidden), isTrue);
      expect(isBackgroundLifecycleState(AppLifecycleState.detached), isTrue);
      expect(isBackgroundLifecycleState(AppLifecycleState.inactive), isFalse);
      expect(isBackgroundLifecycleState(AppLifecycleState.resumed), isFalse);
    });

    test('resumed -> inactive -> paused -> resumed re-locks only at the end',
        () {
      // Real backgrounding goes resumed -> inactive -> paused -> inactive ->
      // resumed. Only the background return should relock.
      expect(
        shouldRelockOnResume(
            AppLifecycleState.inactive, AppLifecycleState.paused),
        isFalse,
      );
      expect(
        shouldRelockOnResume(
            AppLifecycleState.paused, AppLifecycleState.resumed),
        isTrue,
      );
    });
  });

  group('BUG 4 — biometric permission + graceful failure', () {
    test('AndroidManifest declares USE_BIOMETRIC', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(
        manifest,
        contains('android.permission.USE_BIOMETRIC'),
        reason: 'local_auth needs USE_BIOMETRIC to trigger the system prompt',
      );
    });

    test('authenticateWithBiometrics returns false (no throw) on cancelled '
        'prompt', () async {
      LocalAuthPlatform.instance = ThrowingLocalAuthPlatform();
      final service = AppLockService(
        storage: MockSecureStorage(),
        localAuth: LocalAuthentication(),
      );
      expect(await service.authenticateWithBiometrics(), isFalse);
    });

    test('authenticateWithBiometrics returns false (no throw) on exception',
        () async {
      LocalAuthPlatform.instance =
          ThrowingLocalAuthPlatform(throwOnAuthenticate: true);
      final service = AppLockService(
        storage: MockSecureStorage(),
        localAuth: LocalAuthentication(),
      );
      expect(await service.authenticateWithBiometrics(), isFalse);
    });
  });
}
