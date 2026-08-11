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
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freya_pdf/features/security/app_lock_service.dart';
import 'package:freya_pdf/features/security/widgets/app_lock_screen.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';

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

/// Controllable mock local-auth platform used to assert that the lock screen's
/// biometric button triggers the system prompt and unlocks on success.
class ControllableLocalAuthPlatform extends LocalAuthPlatform
    with MockPlatformInterfaceMixin {
  bool authenticateResult = true;
  bool supported = true;
  int authenticateCallCount = 0;
  List<BiometricType> enrolledBiometrics = [BiometricType.fingerprint];

  @override
  Future<bool> deviceSupportsBiometrics() async => supported;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async {
    if (!supported) return [];
    return enrolledBiometrics;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authenticateCallCount++;
    return authenticateResult;
  }
}

/// LocalAuth platform where the first `authenticate()` returns false (simulating
/// a frozen / never-attached system prompt on e.g. HMD Skyline) and every
/// subsequent call returns true — used to assert `AppLockGate`'s retry-once
/// behaviour after the initial auto-prompt fails.
class _RetryLocalAuthPlatform extends LocalAuthPlatform
    with MockPlatformInterfaceMixin {
  int calls = 0;
  bool supported = true;

  @override
  Future<bool> deviceSupportsBiometrics() async => supported;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async {
    if (!supported) return [];
    return [BiometricType.fingerprint];
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    calls++;
    return calls > 1; // first attempt fails, retries succeed
  }
}

/// In-memory [FlutterSecureStoragePlatform] so AppLockGate's internally-built
/// `AppLockService` (which uses a real `FlutterSecureStorage`) can resolve
/// `getBiometricEnabled()` on the test host where the plugin channel is absent.
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
      },
    );

    test('service: legacy install (v2 hash, NO stored length) still verifies '
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
      },
    );
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
    test('notification-shade cycle (inactive -> resumed) does NOT re-lock', () {
      // Dragging the shade: the app briefly becomes inactive then resumes.
      // This must not re-trigger the lock screen nor spam biometrics.
      expect(
        shouldRelockOnResume(
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ),
        isFalse,
      );
    });

    test('true background return (paused -> resumed) DOES re-lock', () {
      expect(
        shouldRelockOnResume(
          AppLifecycleState.paused,
          AppLifecycleState.resumed,
        ),
        isTrue,
      );
      expect(
        shouldRelockOnResume(
          AppLifecycleState.hidden,
          AppLifecycleState.resumed,
        ),
        isTrue,
      );
      expect(
        shouldRelockOnResume(
          AppLifecycleState.detached,
          AppLifecycleState.resumed,
        ),
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

    test(
      'resumed -> inactive -> paused -> resumed re-locks only at the end',
      () {
        // Real backgrounding goes resumed -> inactive -> paused -> inactive ->
        // resumed. Only the background return should relock.
        expect(
          shouldRelockOnResume(
            AppLifecycleState.inactive,
            AppLifecycleState.paused,
          ),
          isFalse,
        );
        expect(
          shouldRelockOnResume(
            AppLifecycleState.paused,
            AppLifecycleState.resumed,
          ),
          isTrue,
        );
      },
    );
  });

  group('BUG 4 — biometric permission + graceful failure', () {
    test('AndroidManifest declares USE_BIOMETRIC', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
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

    test(
      'authenticateWithBiometrics returns false (no throw) on exception',
      () async {
        LocalAuthPlatform.instance = ThrowingLocalAuthPlatform(
          throwOnAuthenticate: true,
        );
        final service = AppLockService(
          storage: MockSecureStorage(),
          localAuth: LocalAuthentication(),
        );
        expect(await service.authenticateWithBiometrics(), isFalse);
      },
    );
  });

  group('BUG 5 — biometrics default-ON + lock-screen button', () {
    test('getBiometricEnabled returns TRUE when nothing is stored', () async {
      final service = AppLockService(storage: MockSecureStorage());
      expect(await service.getBiometricEnabled(), isTrue);
    });

    test('getBiometricEnabled returns FALSE only when stored false', () async {
      final service = AppLockService(storage: MockSecureStorage());
      await service.setBiometricEnabled(false);
      expect(await service.getBiometricEnabled(), isFalse);
    });

    test('isBiometricAvailable && default-on => biometric available', () async {
      final platform = ControllableLocalAuthPlatform();
      LocalAuthPlatform.instance = platform;
      final service = AppLockService(
        storage: MockSecureStorage(),
        localAuth: LocalAuthentication(),
      );
      expect(await service.isBiometricAvailable(), isTrue);
      expect(await service.getBiometricEnabled(), isTrue);
    });

    test(
      'isBiometricUsable returns true when a fingerprint is enrolled',
      () async {
        final platform = ControllableLocalAuthPlatform();
        platform.enrolledBiometrics = [BiometricType.fingerprint];
        LocalAuthPlatform.instance = platform;
        final service = AppLockService(
          storage: MockSecureStorage(),
          localAuth: LocalAuthentication(),
        );
        expect(await service.isBiometricUsable(), isTrue);
      },
    );

    test(
      'isBiometricUsable returns false when NOTHING is enrolled',
      () async {
        final platform = ControllableLocalAuthPlatform();
        platform.enrolledBiometrics = [];
        LocalAuthPlatform.instance = platform;
        final service = AppLockService(
          storage: MockSecureStorage(),
          localAuth: LocalAuthentication(),
        );
        expect(await service.isBiometricUsable(), isFalse);
      },
    );

    test(
      'isBiometricUsable returns false when the device is unsupported',
      () async {
        final platform = ControllableLocalAuthPlatform();
        platform.supported = false;
        LocalAuthPlatform.instance = platform;
        final service = AppLockService(
          storage: MockSecureStorage(),
          localAuth: LocalAuthentication(),
        );
        expect(await service.isBiometricUsable(), isFalse);
      },
    );

    test(
      'isBiometricUsable treats only-face enrollment as usable (prompt still '
      'fine, greyed only when nothing is enrolled)',
      () async {
        final platform = ControllableLocalAuthPlatform();
        platform.enrolledBiometrics = [BiometricType.face];
        LocalAuthPlatform.instance = platform;
        final service = AppLockService(
          storage: MockSecureStorage(),
          localAuth: LocalAuthentication(),
        );
        expect(await service.isBiometricUsable(), isTrue);
      },
    );

    testWidgets(
      'lock screen shows fingerprint button when bio available and tapping '
      'it unlocks on success',
      (tester) async {
        final platform = ControllableLocalAuthPlatform();
        LocalAuthPlatform.instance = platform;
        final service = AppLockService(
          storage: MockSecureStorage(),
          localAuth: LocalAuthentication(),
        );

        var unlocked = false;
        await tester.pumpWidget(
          MaterialApp(
            home: AppLockScreen(
              lockService: service,
              biometricAvailable: true,
              onUnlock: () => unlocked = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final fingerprintButton = find.byIcon(Icons.fingerprint_rounded);
        expect(
          fingerprintButton,
          findsOneWidget,
          reason: 'fingerprint icon must show when biometrics are available',
        );

        await tester.tap(fingerprintButton);
        await tester.pumpAndSettle();

        expect(platform.authenticateCallCount, equals(1));
        expect(
          unlocked,
          isTrue,
          reason: 'successful biometric auth must unlock the screen',
        );
      },
    );

    testWidgets(
      'lock screen GREYS OUT the fingerprint button when biometrics are '
      'unavailable (present but disabled, PIN remains the only path)',
      (tester) async {
        final service = AppLockService(storage: MockSecureStorage());
        await tester.pumpWidget(
          MaterialApp(
            home: AppLockScreen(
              lockService: service,
              biometricAvailable: false,
              onUnlock: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Not hidden — shown in a disabled/greyed state.
        final button = find.ancestor(
          of: find.byIcon(Icons.fingerprint_rounded),
          matching: find.byType(IconButton),
        );
        expect(button, findsOneWidget);
        final iconButton = tester.widget<IconButton>(button);
        expect(
          iconButton.onPressed,
          isNull,
          reason: 'fingerprint button must be disabled (greyed) when '
              'biometrics are unavailable',
        );
      },
    );
  });

  group('BUG 6 — AppLockGate cold-start biometric prompt', () {
    testWidgets(
      'AppLockGate fires the biometric prompt on cold start when lock is '
      'enabled and biometrics are available',
      (tester) async {
        // AppLockGate builds its own AppLockService with a default
        // LocalAuthentication, which delegates to the global
        // LocalAuthPlatform, so overriding the platform here controls both the
        // availability check and the authenticate() call. Its internal
        // AppLockService also uses a default FlutterSecureStorage, so back it
        // with an in-memory platform (default-on biometrics → true).
        final platform = ControllableLocalAuthPlatform();
        LocalAuthPlatform.instance = platform;
        FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsProvider(SettingsService(prefs));
        await settings.setAppLockEnabled(true);

        var unlocked = false;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ],
            child: MaterialApp(
              home: AppLockGate(
                child: Builder(
                  builder: (_) {
                    unlocked = true;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );
        // Let _checkLock's async availability/enabled checks complete, then the
        // post-frame callback (which fires the system biometric prompt) run.
        // Several pumps are needed because the deferral schedules a fresh
        // post-frame callback that itself performs another await.
        await tester.pumpAndSettle();
        // The auto-prompt defers its system prompt by 500ms (so the Android
        // Activity is confirmed resumed before BiometricPrompt attaches on e.g.
        // HMD Skyline); advance the fake clock past that delay so the prompt
        // actually fires and the mock's authenticate call is counted.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(
          platform.authenticateCallCount,
          equals(1),
          reason: 'cold start with biometrics available must auto-prompt',
        );

        // Successful auth unlocks the gate.
        expect(unlocked, isTrue);
      },
    );

    testWidgets(
      'AppLockGate auto-fires the biometric prompt again on a true '
      'background → resume transition',
      (tester) async {
        // Mashal override: on resume the biometric prompt should auto-trigger
        // too (PIN is only the fallback when no biometrics are available).
        final platform = ControllableLocalAuthPlatform();
        LocalAuthPlatform.instance = platform;
        FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsProvider(SettingsService(prefs));
        await settings.setAppLockEnabled(true);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ],
            child: MaterialApp(
              home: AppLockGate(child: const SizedBox.shrink()),
            ),
          ),
        );
        // Cold-start auto-prompt fires and unlocks.
        await tester.pumpAndSettle();
        // Advance past the 500ms pre-authenticate delay so the prompt fires.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(platform.authenticateCallCount, equals(1));

        // Simulate a true background → resume cycle (paused → resumed).
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        // Advance past the 500ms pre-authenticate delay on the resume prompt.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(
          platform.authenticateCallCount,
          equals(2),
          reason: 'resume with biometrics available must auto-prompt again',
        );
      },
    );

    testWidgets(
      'AppLockGate retries the biometric prompt ONCE after the first attempt '
      'fails (HMD Skyline / transient prompt-attach failure)',
      (tester) async {
        // First authenticate returns false (e.g. BiometricPrompt failed to
        // attach), a retry after ~1s returns true and should unlock.
        final platform = _RetryLocalAuthPlatform();
        LocalAuthPlatform.instance = platform;
        FlutterSecureStoragePlatform.instance = MockSecureStoragePlatform();

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final settings = SettingsProvider(SettingsService(prefs));
        await settings.setAppLockEnabled(true);

        var unlocked = false;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ],
            child: MaterialApp(
              home: AppLockGate(
                child: Builder(
                  builder: (_) {
                    unlocked = true;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );

        // Cold start: post-frame callback defers 500ms, first attempt fails.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(
          platform.calls,
          greaterThanOrEqualTo(1),
          reason: 'first attempt must be attempted',
        );

        // Advance past the ~1s retry delay, then the deferred 500ms prompt
        // delay of the second attempt; the retry succeeds and unlocks.
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(
          platform.calls,
          greaterThanOrEqualTo(2),
          reason: 'a failed first attempt must be retried once',
        );
        expect(unlocked, isTrue,
            reason: 'the successful retry must unlock the gate');
      },
    );
  });
}
