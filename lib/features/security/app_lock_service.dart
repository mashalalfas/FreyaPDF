// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';

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
class AppLockService {
  static const _kPinHash = 'app_lock_pin_hash';
  static const _kBiometricEnabled = 'app_lock_biometric';

  // PBKDF2 parameters
  static const _pbkdf2Prefix = 'pbkdf2_sha256';
  static const _pbkdf2Iterations = 100000;
  static const _pbkdf2SaltLength = 16;
  static const _pbkdf2KeyLength = 32;

  final FlutterSecureStorage? _storage;
  final LocalAuthentication? _localAuth;

  AppLockService({FlutterSecureStorage? storage, LocalAuthentication? localAuth})
      : _storage = storage,
        _localAuth = localAuth;

  FlutterSecureStorage get _store => _storage ?? const FlutterSecureStorage();
  LocalAuthentication get _auth => _localAuth ?? LocalAuthentication();

  // ── PIN ──

  /// Set the user's PIN, overwriting any previously stored value.
  /// Uses the v2 PBKDF2 format.
  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _deriveKeyPbkdf2(pin, salt, _pbkdf2Iterations);
    final value =
        '$_pbkdf2Prefix\$$_pbkdf2Iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
    await _store.write(key: _kPinHash, value: value);
  }

  /// Verify a PIN. Returns `true` on match.
  ///
  /// If the stored value is in the legacy v1 format, a successful match
  /// is migrated to v2 (PBKDF2) before returning. The verify call still
  /// succeeds from the caller's perspective either way.
  Future<bool> verifyPin(String pin) async {
    final stored = await _store.read(key: _kPinHash);
    if (stored == null) return false;

    if (_isLegacyFormat(stored)) {
      return _verifyLegacyAndMigrate(pin, stored);
    }
    return _verifyPbkdf2(pin, stored);
  }

  Future<bool> hasPin() async =>
      (await _store.read(key: _kPinHash)) != null;

  Future<void> clearPin() async {
    await _store.delete(key: _kPinHash);
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

  Future<bool> getBiometricEnabled() async =>
      (await _store.read(key: _kBiometricEnabled)) == 'true';

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
