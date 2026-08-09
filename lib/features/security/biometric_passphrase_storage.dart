import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage for the biometric-unlock passphrase.
///
/// On Android the value is encrypted at rest via the Android Keystore
/// (EncryptedSharedPreferences under the hood). This is strictly stronger
/// than [SharedPreferences], which is a plain XML file that any process
/// with root can read.
///
/// On a one-time migration we read any legacy value still stored in
/// [SharedPreferences] under `_freya_bio_passphrase`, copy it into the
/// secure store, and then erase the plaintext copy.
class BiometricPassphraseStorage {
  BiometricPassphraseStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = '_freya_bio_passphrase';
  static const _legacyPrefsKey = '_freya_bio_passphrase';

  final FlutterSecureStorage _storage;

  /// Read the stored biometric passphrase.
  ///
  /// Performs a one-time migration from the legacy SharedPreferences
  /// entry on first call so existing users keep their saved passphrase.
  Future<String?> read() async {
    await _migrateFromLegacyPrefsIfNeeded();
    return _storage.read(key: _key);
  }

  /// Persist [passphrase] for the next biometric unlock.
  Future<void> write(String passphrase) async {
    await _storage.write(key: _key, value: passphrase);
  }

  /// Clear the stored biometric passphrase (e.g. when the user resets
  /// their session passphrase).
  Future<void> clear() async {
    await _storage.delete(key: _key);
  }

  /// If a legacy plaintext entry exists, copy it to the secure store
  /// and remove the plaintext copy. Idempotent.
  Future<void> _migrateFromLegacyPrefsIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_legacyPrefsKey);
      if (legacy == null) return;
      // Already present in secure store? Then the plaintext copy is just
      // leftover — clear it and stop. Otherwise copy it over first.
      final existing = await _storage.read(key: _key);
      if (existing == null) {
        await _storage.write(key: _key, value: legacy);
      }
      await prefs.remove(_legacyPrefsKey);
    } catch (_) {
      // Best-effort migration — never block unlock on this.
    }
  }
}
