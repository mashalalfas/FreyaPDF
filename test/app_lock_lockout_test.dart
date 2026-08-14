// Copyright (c) 2026 Freya. All rights reserved.
// Prove-It tests for the brute-force lockout added to AppLockService.
//
// Verifies the CRITICAL security control: a PIN lock cannot be brute-forced
// in an unbounded loop. The lock state is persisted (survives process kill),
// escalates in duration, and is cleared only by a correct PIN.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freya_pdf/features/security/app_lock_service.dart';

/// In-memory fake for FlutterSecureStorage so PIN hashing tests stay hermetic.
class MockSecureStorage extends FlutterSecureStorage {
  final _store = <String, String>{};

  MockSecureStorage() : super();

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
    _store[key] = value ?? '';
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
    return _store[key];
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
    _store.remove(key);
  }
}

void main() {
  const correctPin = '123456';

  /// SharedPreferences backing store shared across the whole test. Recreating
  /// AppLockService with the same store simulates a fresh process reading the
  /// same persisted lockout state (used by the kill-persistence test).
  late SharedPreferences prefs;

  AppLockService buildService() => AppLockService(
        storage: MockSecureStorage(),
        prefs: prefs,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('lock engages after N consecutive wrong PINs', () async {
    final service = buildService();
    await service.setPin(correctPin);

    // The first (threshold - 1) failures do not lock.
    for (var i = 0; i < AppLockService.lockoutThreshold1 - 1; i++) {
      expect(await service.verifyPin('999999'), isFalse);
      expect(await service.isLockedOut(), isFalse,
          reason: 'must not lock before the first threshold');
    }

    // On the threshold failure the lock engages.
    expect(await service.verifyPin('999999'), isFalse);
    expect(await service.isLockedOut(), isTrue,
        reason: '${AppLockService.lockoutThreshold1} consecutive failures '
            'must engage the lockout');
    // While locked the correct PIN is refused too.
    expect(await service.verifyPin(correctPin), isFalse);
  });

  test('verifyPin reports locked-out as a failure without brute-forcing',
      () async {
    final service = buildService();
    await service.setPin(correctPin);

    // Drive straight to a locked state by seeding the persisted counter.
    final storage = service;
    for (var i = 0; i < AppLockService.lockoutThreshold1; i++) {
      await storage.verifyPin('999999');
    }
    expect(await service.isLockedOut(), isTrue);

    // While locked, every verifyPin returns false WITHOUT incrementing the
    // attempt counter further (no wasted PBKDF2, no lock escalation).
    final attemptsBefore = await service.getFailedAttempts();
    await service.verifyPin('888888');
    await service.verifyPin('777777');
    expect(await service.getFailedAttempts(), attemptsBefore,
        reason: 'locked verifies must not burn attempts');
  });

  test('lockout duration escalates through backoff tiers', () async {
    final service = buildService();
    await service.setPin(correctPin);

    // Tier 1: reaching lockoutThreshold1 yields lockoutDuration1 (30s).
    for (var i = 0; i < AppLockService.lockoutThreshold1; i++) {
      await service.verifyPin('999999');
    }
    final tier1 = await service.getLockoutRemaining();
    expect(tier1, greaterThan(Duration.zero));
    expect(tier1.inSeconds, lessThanOrEqualTo(
        AppLockService.lockoutDuration1.inSeconds + 1));

    // Tier 2: reaching lockoutThreshold2 yields the longer duration.
    for (var i = 0;
        i < AppLockService.lockoutThreshold2 - AppLockService.lockoutThreshold1;
        i++) {
      await service.recordFailedAttempt();
    }
    final tier2 = await service.getLockoutRemaining();
    expect(tier2, greaterThan(tier1),
        reason: 'second tier must be strictly longer than the first');

    // Tier 3: reaching lockoutThreshold3 yields the longest duration.
    for (var i = 0;
        i < AppLockService.lockoutThreshold3 - AppLockService.lockoutThreshold2;
        i++) {
      await service.recordFailedAttempt();
    }
    final tier3 = await service.getLockoutRemaining();
    expect(tier3, greaterThan(tier2),
        reason: 'third tier must be strictly longer than the second');

    // Sanity: the configured durations are what we expect.
    expect(AppLockService.lockoutDuration1, const Duration(seconds: 30));
    expect(AppLockService.lockoutDuration2, const Duration(minutes: 5));
    expect(AppLockService.lockoutDuration3, const Duration(minutes: 30));
  });

  test('correct PIN clears the failure counter', () async {
    final service = buildService();
    await service.setPin(correctPin);

    for (var i = 0; i < 3; i++) {
      await service.verifyPin('999999');
    }
    expect(await service.getFailedAttempts(), 3);

    expect(await service.verifyPin(correctPin), isTrue);
    expect(await service.getFailedAttempts(), 0,
        reason: 'a successful verify must reset the attempt history');
    expect(await service.isLockedOut(), isFalse);
  });

  test('lockout state persists across service re-instantiation', () async {
    // First service instance burns through the threshold.
    final first = buildService();
    await first.setPin(correctPin);
    for (var i = 0; i < AppLockService.lockoutThreshold1; i++) {
      await first.verifyPin('999999');
    }
    expect(await first.isLockedOut(), isTrue);

    // A brand-new instance (fresh AppLockService, same persisted store)
    // simulates the app being killed and relaunched. It must still see the
    // same lockout because the counter/expiry live in SharedPreferences.
    final second = buildService();
    expect(await second.isLockedOut(), isTrue,
        reason: 'lock must survive a process kill and restart');
    expect(await second.getFailedAttempts(), AppLockService.lockoutThreshold1);

    // And it refuses to verify the correct PIN while still locked.
    expect(await second.verifyPin(correctPin), isFalse);
  });

  group('confirmCurrentPin — PIN change/remove re-auth gate', () {
    // The settings UI calls confirmCurrentPin before setPin/clearPin. This is
    // the exact gate that stops a bystander from silently resetting/removing
    // the lock, so it must (a) reject a wrong PIN, (b) require a PIN that
    // actually exists, and (c) allow a correct current PIN through.

    test('rejects a wrong current PIN so a change/remove is blocked', () async {
      final service = buildService();
      await service.setPin(correctPin);
      expect(await service.confirmCurrentPin('111111'), isFalse,
          reason: 'wrong current PIN must not authorise a lock change');
    });

    test('rejects when no PIN is set (nothing to authorise against)', () async {
      final service = buildService();
      expect(await service.confirmCurrentPin(correctPin), isFalse,
          reason: 'no stored PIN → nothing to prove knowledge of');
    });

    test('grants a correct current PIN for change/remove', () async {
      final service = buildService();
      await service.setPin(correctPin);
      expect(await service.confirmCurrentPin(correctPin), isTrue);
    });

    test('a successful re-auth clears the failure counter', () async {
      final service = buildService();
      await service.setPin(correctPin);
      // A few warm-up wrong attempts.
      await service.verifyPin('111111');
      await service.verifyPin('222222');
      expect(await service.getFailedAttempts(), 2);

      // Correct current PIN passes the gate and resets the counter.
      expect(await service.confirmCurrentPin(correctPin), isTrue);
      expect(await service.getFailedAttempts(), 0);
    });
  });
}
