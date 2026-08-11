// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing app-level PIN and biometric authentication.
///
/// PIN storage format versions (selected by inspecting the prefix):
///
///   v1 (legacy): `<salt-base64>:<sha256-hash-base64>`
///                Single-round SHA-256 over `<salt>:<pin>` with a 16-byte
///                random salt. Brute-forceable on a stolen device because
///                PINs carry low entropy. Still accepted; on the first
///                successful verify the entry is silently re-written as v2.
///
///   v2 (current): `pbkdf2_sha256$<iterations>$<salt-base64>$<hash-base64>`
///                PBKDF2-HMAC-SHA256 with a 16-byte random salt and
///                100,000 iterations (matches the `EncryptionService`
///                pattern but with a lower round count appropriate for
///                low-entropy PINs). 32-byte derived key.
///
/// Biometric state is stored separately at `app_lock_biometric`.
///
/// Brute-force lockout state is persisted in [SharedPreferences] so it
/// survives a process kill — a determined attacker cannot bypass the
/// backoff merely by restarting the app. The failure counter and the
/// absolute lockout expiry (epoch milliseconds) are both stored; on a
/// fresh build the pref keys ship empty/default so no lockout is assumed.
/// Run in a background isolate: derive a PBKDF2 hash off the UI thread so
/// setting a PIN does not freeze the UI. Inputs/outputs are isolate-safe
/// plain values (String / Uint8List via [Isolate.run]).
Uint8List _derivePbkdf2InIsolate(String pin, Uint8List salt, int iterations) {
  // 32-byte derived key (matches AppLockService._pbkdf2KeyLength).
  const keyLength = 32;
  final params = Pbkdf2Parameters(salt, iterations, keyLength);
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(params);
  return Uint8List.fromList(
    pbkdf2.process(Uint8List.fromList(utf8.encode(pin))),
  );
}

class AppLockService {
  static const _kPinHash = 'app_lock_pin_hash';
  static const _kPinLength = 'app_lock_pin_length';
  static const _kBiometricEnabled = 'app_lock_biometric';

  // ── Brute-force lockout configuration ──
  // Tiered exponential backoff. After `threshold` consecutive failures the
  // lock engages for `duration`. All values are overridable so a host or test
  // can inject a stricter/looser policy.
  static const int lockoutThreshold1 = 5;
  static const Duration lockoutDuration1 = Duration(seconds: 30);
  static const int lockoutThreshold2 = 10;
  static const Duration lockoutDuration2 = Duration(minutes: 5);
  static const int lockoutThreshold3 = 15;
  static const Duration lockoutDuration3 = Duration(minutes: 30);

  /// Persistent (SharedPreferences) key holding the consecutive-failure count.
  static const _kFailedAttempts = 'app_lock_failed_attempts';

  /// Persistent (SharedPreferences) key holding the absolute lockout expiry
  /// as epoch milliseconds (0 = not locked).
  static const _kLockedUntil = 'app_lock_locked_until';

  // PBKDF2 parameters
  static const _pbkdf2Prefix = 'pbkdf2_sha256';
  static const _pbkdf2Iterations = 100000;
  static const _pbkdf2SaltLength = 16;
  static const _pbkdf2KeyLength = 32;

  final FlutterSecureStorage? _storage;
  final LocalAuthentication? _localAuth;
  final SharedPreferences? _prefs;

  AppLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
    SharedPreferences? prefs,
  })  : _storage = storage,
        _localAuth = localAuth,
        _prefs = prefs;

  FlutterSecureStorage get _store => _storage ?? const FlutterSecureStorage();
  LocalAuthentication get _auth => _localAuth ?? LocalAuthentication();
  Future<SharedPreferences> get _preferences async =>
      _prefs ?? await SharedPreferences.getInstance();

  /// Clear the persistent brute-force counter. Called after a correct PIN so
  /// the lock never carries a stale failure history into a new session.
  Future<void> clearFailedAttempts() async {
    final prefs = await _preferences;
    await prefs.remove(_kFailedAttempts);
  }

  /// Number of consecutive incorrect PIN attempts recorded.
  Future<int> getFailedAttempts() async {
    final prefs = await _preferences;
    return prefs.getInt(_kFailedAttempts) ?? 0;
  }

  /// Lockout duration (backoff tier) for the current failure count.
  Duration lockoutDurationFor(int attempts) {
    if (attempts >= lockoutThreshold3) return lockoutDuration3;
    if (attempts >= lockoutThreshold2) return lockoutDuration2;
    if (attempts >= lockoutThreshold1) return lockoutDuration1;
    return Duration.zero;
  }

  /// True if a lockout is currently active (now < expiry).
  Future<bool> isLockedOut() async {
    return (await getLockoutRemaining()) > Duration.zero;
  }

  /// Remaining lockout time; [Duration.zero] when not locked.
  Future<Duration> getLockoutRemaining() async {
    final prefs = await _preferences;
    final expiry = prefs.getInt(_kLockedUntil) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingMs = expiry - now;
    return remainingMs > 0 ? Duration(milliseconds: remainingMs) : Duration.zero;
  }

  /// Record a failed attempt, escalating the backoff tier, and return the
  /// new lockout duration if the lock has been engaged (else [Duration.zero]).
  Future<Duration> recordFailedAttempt() async {
    final prefs = await _preferences;
    final next = (prefs.getInt(_kFailedAttempts) ?? 0) + 1;
    await prefs.setInt(_kFailedAttempts, next);
    final duration = lockoutDurationFor(next);
    if (duration > Duration.zero) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_kLockedUntil, now + duration.inMilliseconds);
    }
    return duration;
  }

  // ── PIN ──

  /// Set the user's PIN, overwriting any previously stored value.
  /// Uses the v2 PBKDF2 format. The key derivation runs in a background
  /// isolate so the call does not block the UI thread.
  /// Also persists the chosen PIN length so the lock screen can auto-submit
  /// at exactly the configured length.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    // Derive off the UI thread (keeps the same v2 format / iteration count).
    final hash = await Isolate.run(
      () => _derivePbkdf2InIsolate(
        pin,
        salt,
        _pbkdf2Iterations,
      ),
    );
    final value =
        '$_pbkdf2Prefix\$$_pbkdf2Iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
    await _store.write(key: _kPinHash, value: value);
    // Range-check the length (defensive: treat out-of-range as unset so the
    // legacy fallback / verify-at-current-length path applies).
    if (pin.length >= 4 && pin.length <= 6) {
      await _store.write(key: _kPinLength, value: '${pin.length}');
    } else {
      await _store.delete(key: _kPinLength);
    }
  }

  /// The stored PIN length chosen via [setPin], or `null` when unset.
  ///
  /// Legacy installs (like the current one) have no stored length; a `null`
  /// return tells the lock screen to fall back to a manual confirm/check
  /// button that verifies at the current buffer length (4-6 digits).
  Future<int?> getPinLength() async {
    final raw = await _store.read(key: _kPinLength);
    if (raw == null) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 4 || parsed > 6) return null;
    return parsed;
  }

  /// Verify a PIN. Returns `true` on match, `false` otherwise (including when
  /// the lock is currently engaged).
  ///
  /// The lock is checked first: if a lockout is active, verification is refused
  /// without consuming PBKDF2 work. On a correct match the failure counter is
  /// cleared. On a wrong match the counter is incremented and, at a tier
  /// threshold, a progressive backoff lock is engaged (persisted, so it
  /// survives a process kill).
  ///
  /// If the stored value is in the legacy v1 format, a successful match is
  /// migrated to v2 (PBKDF2) before returning.
  Future<bool> verifyPin(String pin) async {
    if (await isLockedOut()) return false;

    final stored = await _store.read(key: _kPinHash);
    if (stored == null) return false;

    bool ok;
    if (_isLegacyFormat(stored)) {
      ok = await _verifyLegacyAndMigrate(pin, stored);
    } else {
      ok = _verifyPbkdf2(pin, stored);
    }

    if (ok) {
      await clearFailedAttempts();
    } else {
      await recordFailedAttempt();
    }
    return ok;
  }

  Future<bool> hasPin() async =>
      (await _store.read(key: _kPinHash)) != null;

  /// Re-authentication gate used before a destructive lock change (change or
  /// remove). Returns true only if a PIN exists AND [pin] matches it — so a
  /// caller may proceed with setPin/clearPin only after proving knowledge of
  /// the current PIN. When no PIN is set there is nothing to protect, so it
  /// returns false (a caller setting a brand-new PIN must not require one).
  Future<bool> confirmCurrentPin(String pin) async {
    if (!await hasPin()) return false;
    return verifyPin(pin);
  }

  Future<void> clearPin() async {
    await _store.delete(key: _kPinHash);
    await _store.delete(key: _kPinLength);
    await _store.delete(key: _kBiometricEnabled);
  }

  // ── Biometric ──

  Future<bool> isBiometricAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Whether a biometric is actually usable for unlock: the device supports
  /// biometrics (hardware + secure hardware), can check biometrics, AND has at
  /// least one enrolled biometric. local_auth's `canCheckBiometrics` can be
  /// true with no enrolled credentials, so this additionally requires a non-
  /// empty `getAvailableBiometrics()` result. When false, the lock screen shows
  /// a greyed-out fingerprint button and falls back to PIN only.
  Future<bool> isBiometricUsable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Whether biometric unlock is enabled.
  ///
  /// Default-ON semantics: biometrics are enabled unless the user has
  /// *explicitly* opted out by storing `false`. A fresh install, or a user who
  /// set a PIN before the toggle existed, has never stored a value — returning
  /// true for that case means fingerprint unlock works out of the box for
  /// every user who sets a PIN on a device that supports biometrics (which is
  /// the expected/ergonomic behavior; see device-feedback round 2).
  Future<bool> getBiometricEnabled() async {
    final stored = await _store.read(key: _kBiometricEnabled);
    if (stored == null || stored.isEmpty) return true;
    return stored == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _store.write(
        key: _kBiometricEnabled, value: enabled ? 'true' : 'false');
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Freya PDF',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  // ── Format detection ──

  /// Legacy v1 entries are `salt:hash` with no `$` separator.
  bool _isLegacyFormat(String stored) =>
      !stored.startsWith('$_pbkdf2Prefix\$');

  // ── v2 (PBKDF2) verify ──

  bool _verifyPbkdf2(String pin, String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 4) return false;
    if (parts[0] != _pbkdf2Prefix) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    Uint8List salt;
    Uint8List expected;
    try {
      salt = base64.decode(parts[2]);
      expected = base64.decode(parts[3]);
    } catch (_) {
      return false;
    }
    final actual = _deriveKeyPbkdf2(pin, salt, iterations);
    return _constantTimeEqualsBytes(actual, expected);
  }

  // ── v1 (legacy SHA-256) verify ──

  bool _verifyLegacy(String pin, String stored) {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expected = parts[1];
    final input = utf8.encode('$salt:$pin');
    final digest = SHA256Digest().process(input);
    final actual = base64.encode(digest);
    return _constantTimeEquals(actual, expected);
  }

  /// Verify a v1 entry and, on match, transparently upgrade it to v2.
  /// The verify call still returns `true` either way; migration just
  /// ensures the next call uses the stronger PBKDF2 path.
  Future<bool> _verifyLegacyAndMigrate(String pin, String stored) async {
    if (!_verifyLegacy(pin, stored)) return false;
    // Re-derive using the stronger KDF and overwrite the legacy entry.
    // Failure to migrate is non-fatal — the user is already unlocked.
    try {
      await setPin(pin);
    } catch (_) {
      // Migration is best-effort; do not propagate.
    }
    return true;
  }

  // ── Hashing helpers ──

  Uint8List _generateSalt() {
    final rng = Random.secure();
    final bytes = Uint8List(_pbkdf2SaltLength);
    for (var i = 0; i < _pbkdf2SaltLength; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  /// PBKDF2-HMAC-SHA256 derivation. Mirrors the `EncryptionService`
  /// pattern but uses 100k iterations — appropriate for low-entropy
  /// PINs where 600k (the OWASP-recommended count for password-derived
  /// keys) would be needlessly slow on the unlock critical path.
  Uint8List _deriveKeyPbkdf2(String pin, Uint8List salt, int iterations) {
    final params = Pbkdf2Parameters(salt, iterations, _pbkdf2KeyLength);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(params);
    return Uint8List.fromList(
      pbkdf2.process(Uint8List.fromList(utf8.encode(pin))),
    );
  }

  // ── Constant-time comparisons ──
  // Defends against timing oracles that could otherwise leak prefix
  // matches during hash comparison.

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  bool _constantTimeEqualsBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
