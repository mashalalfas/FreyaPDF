// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart';

/// Encrypts and decrypts PDF bytes using AES-256-GCM.
///
/// Format:
///   "FREYA" + version(1) + iv(12) + salt(32) + ciphertext + auth_tag(16)
///
/// Key derivation: PBKDF2-SHA256, 600,000 iterations, 32-byte key.
class EncryptionService {
  static const _magic = [0x46, 0x52, 0x45, 0x59, 0x41]; // "FREYA"
  static const _magicLength = 5;
  static const _version = 2;
  static const _saltLength = 32;
  static const _ivLength = 12;

  /// PBKDF2-HMAC-SHA256 iteration count (OWASP recommendation). Exposed as a
  /// public constant so a test asserts the exact configured value stays 600k —
  /// a silent drop to weaker KDF parameters fails CI rather than sliding by.
  static const iterations = 600000;

  /// Offset of the version byte = length of the magic header.
  static const _versionOffset = _magicLength;

  /// Offset of the IV = magic + version.
  static const _ivOffset = _versionOffset + 1;

  /// Encrypt raw bytes (e.g. a PDF) with the given passphrase.
  /// Returns raw bytes (magic + header + ciphertext).
  static Uint8List encryptBytes(Uint8List plaintext, String passphrase) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLength, (_) => random.nextInt(256)),
    );
    final iv = IV.fromSecureRandom(_ivLength);

    final key = _deriveKey(passphrase, salt);
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final encrypted = encrypter.encryptBytes(plaintext, iv: iv);

    // Build output buffer
    final builder = BytesBuilder();
    builder.add(_magic);
    builder.addByte(_version);
    builder.add(iv.bytes);
    builder.add(salt);
    builder.add(encrypted.bytes);

    return builder.toBytes();
  }

  /// Decrypt bytes back to plaintext.
  /// Throws [EncryptionException] if passphrase is wrong or data is corrupt.
  static Uint8List decryptBytes(Uint8List data, String passphrase) {
    if (data.length < _minLength) {
      throw const EncryptionException('File too small to be encrypted');
    }

    // Verify magic
    for (var i = 0; i < _magicLength; i++) {
      if (data[i] != _magic[i]) {
        throw const EncryptionException('Invalid file format');
      }
    }

    final version = data[_versionOffset];
    if (version > _version) {
      throw EncryptionException('Unsupported version: $version');
    }

    final iv = IV(data.sublist(_ivOffset, _ivOffset + _ivLength));
    final salt = data.sublist(
      _ivOffset + _ivLength,
      _ivOffset + _ivLength + _saltLength,
    );
    final ciphertext = data.sublist(_ivOffset + _ivLength + _saltLength);

    final key = _deriveKey(passphrase, Uint8List.fromList(salt));
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

    try {
      final encrypted = Encrypted(ciphertext);
      return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
    } catch (e) {
      throw const EncryptionException('Wrong passphrase or corrupted file');
    }
  }

  /// Derive a 32-byte key from passphrase + salt using PBKDF2.
  static Key _deriveKey(String passphrase, Uint8List salt) {
    final params = Pbkdf2Parameters(salt, iterations, 32);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(params);
    final keyBytes = pbkdf2.process(
      Uint8List.fromList(utf8.encode(passphrase)),
    );
    return Key(keyBytes);
  }

  static const _minLength =
      _magicLength + 1 + _ivLength + _saltLength; // magic + version + iv + salt

  /// Encrypt a file on disk and write the encrypted payload to [outputPath]
  /// (or to "`<inputPath>.enc`" if omitted). Returns the final output path.
  /// Writes header + ciphertext in one pass; renames temp file atomically.
  /// The heavy read + PBKDF2 + AES-GCM work runs in a background isolate so
  /// very large PDFs don't block the UI thread.
  static Future<String> encryptFile(
    String inputPath,
    String passphrase, {
    String? outputPath,
  }) async {
    final outPath = outputPath ?? '$inputPath.enc';
    final tmpPath = '$outPath.tmp';
    final outputFile = File(tmpPath);

    try {
      // Clear any stale temp file left by a previous interrupted run.
      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      // Read + encrypt off the main isolate (single copy: only the ciphertext
      // crosses the boundary). `encrypt`/`pointycastle` are pure-Dart and
      // isolate-safe; the entrypoint is a static method because isolate
      // entrypoints cannot capture closures/instance state.
      final encrypted = await Isolate.run(() {
        return _encryptFileInIsolate(inputPath, passphrase);
      });

      // Write the whole payload in a single atomic pass (temp file → rename).
      // This avoids corrupting an existing .enc target on a partial failure.
      await outputFile.writeAsBytes(encrypted, mode: FileMode.write);

      // Overwrite-safe commit. On POSIX rename() replaces atomically; on
      // Windows rename() to an existing path throws, so remove any stale target
      // first so re-encrypting an already-encrypted file does not crash.
      final target = File(outPath);
      if (await target.exists()) {
        await target.delete();
      }
      await outputFile.rename(outPath);
      return outPath;
    } catch (_) {
      // Best-effort cleanup of the temp file; never mask the original error.
      try {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Decrypt an encrypted file and return the plaintext bytes.
  /// Throws [EncryptionException] if the file is corrupt or the passphrase is wrong.
  /// The heavy read + PBKDF2 + AES-GCM work runs in a background isolate, so
  /// decrypting large files won't block the UI thread.
  static Future<Uint8List> decryptFile(String encPath, String passphrase) async {
    // Errors thrown inside an isolate surface as [RemoteError], losing the
    // original [EncryptionException] type. The isolate therefore returns a
    // result carrier and the typed exception is rethrown here so callers that
    // `on EncryptionException` still work unchanged.
    final result = await Isolate.run(() {
      return _decryptFileInIsolate(encPath, passphrase);
    });
    if (result.error != null) {
      throw EncryptionException(result.error!);
    }
    return result.bytes!;
  }

  /// Isolate entrypoint for [encryptFile]: reads [inputPath] synchronously and
  /// reuses the in-memory [encryptBytes] path so the ciphertext format/header
  /// is identical to prior versions. Returns raw encrypted bytes.
  static Uint8List _encryptFileInIsolate(String inputPath, String passphrase) {
    final plaintext = File(inputPath).readAsBytesSync();
    return encryptBytes(plaintext, passphrase);
  }

  /// Isolate entrypoint for [decryptFile]: reads [encPath] synchronously and
  /// reuses the in-memory [decryptBytes] path. Decrypt failures — wrong
  /// passphrase, corrupt/too-small/foreign data — are captured as a message
  /// rather than thrown, so the caller can surface a typed [EncryptionException].
  static _IsolateDecryptResult _decryptFileInIsolate(
    String encPath,
    String passphrase,
  ) {
    final data = File(encPath).readAsBytesSync();
    try {
      return _IsolateDecryptResult(decryptBytes(data, passphrase), null);
    } on EncryptionException catch (e) {
      return _IsolateDecryptResult(null, e.message);
    }
  }
}

/// Result carrier for isolate-based decryption. Kept private so the typed
/// [EncryptionException] message survives the isolate transfer boundary
/// (errors thrown in an isolate lose their original type).
class _IsolateDecryptResult {
  final Uint8List? bytes;
  final String? error;
  const _IsolateDecryptResult(this.bytes, this.error);
}

class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);

  @override
  String toString() => 'EncryptionException: $message';
}
