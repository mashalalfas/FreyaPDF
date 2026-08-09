import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:freya_pdf/features/encryption/encryption_service.dart';
import 'package:freya_pdf/features/security/biometric_passphrase_storage.dart';

/// Manages passphrase state and file encryption/decryption.
///
/// Single source of truth for passphrase. autoEncrypt lives in SettingsProvider.
class EncryptionProvider extends ChangeNotifier {
  String? _passphrase;

  String? get passphrase => _passphrase;
  bool get isLocked => _passphrase == null || _passphrase!.isEmpty;
  bool get hasPassphrase => _passphrase != null && _passphrase!.isNotEmpty;

  void setPassphrase(String? value) {
    _passphrase = value;
    notifyListeners();
  }

  Future<void> clearPassphrase() async {
    _passphrase = null;
    // Also clear stored biometric passphrase from secure storage
    await BiometricPassphraseStorage().clear();
    notifyListeners();
  }

  /// Encrypt a .pdf file on disk. Returns the new .pdf.enc path.
  /// Original .pdf file is NOT deleted — caller decides.
  /// Atomic write — write to temp file first, then rename.
  Future<String> encryptFile(String pdfPath) async {
    if (_passphrase == null || _passphrase!.isEmpty) {
      throw const EncryptionException('No passphrase set');
    }
    final file = File(pdfPath);
    if (!await file.exists()) {
      throw EncryptionException('File not found: $pdfPath');
    }
    return await EncryptionService.encryptFile(pdfPath, _passphrase!);
  }

  /// Decrypt a .pdf.enc file. Returns the plaintext PDF bytes.
  /// Throws EncryptionException on wrong passphrase.
  Future<Uint8List> decryptFile(String encPath) async {
    if (_passphrase == null || _passphrase!.isEmpty) {
      throw const EncryptionException(
          'No passphrase set — enter passphrase to open encrypted file');
    }
    final file = File(encPath);
    if (!await file.exists()) {
      throw EncryptionException('File not found: $encPath');
    }
    return EncryptionService.decryptFile(encPath, _passphrase!);
  }

  /// Re-encrypt an already-decrypted file (save flow).
  /// Accepts plaintext bytes in-memory — doesn't re-read from disk.
  /// Atomic write — temp file first, then rename.
  Future<void> reEncryptFile(String encPath, Uint8List plaintext) async {
    if (_passphrase == null || _passphrase!.isEmpty) {
      throw const EncryptionException('No passphrase set');
    }

    final encrypted = EncryptionService.encryptBytes(plaintext, _passphrase!);

    final tmpPath = '$encPath.tmp';
    await File(tmpPath).writeAsBytes(encrypted);
    await File(tmpPath).rename(encPath);
  }
}
