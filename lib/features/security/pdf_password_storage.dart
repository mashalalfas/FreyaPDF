import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Secure, per-file storage for passwords belonging to external PDFs.
///
/// Password values never enter SharedPreferences, backups, logs, or the
/// app-wide FeyaPDF encryption passphrase. The secure index contains only
/// opaque storage keys so the entries can be cleared later.
class PdfPasswordStorage {
  PdfPasswordStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _indexKey = '_feya_pdf_password_index';
  static const _keyPrefix = '_feya_pdf_password_';

  final FlutterSecureStorage _storage;

  Future<String?> read(String filePath) async {
    return _storage.read(key: _keyFor(filePath));
  }

  Future<void> write(String filePath, String password) async {
    final key = _keyFor(filePath);
    await _storage.write(key: key, value: password);
    final keys = await _readIndex();
    if (!keys.contains(key)) {
      keys.add(key);
      await _writeIndex(keys);
    }
  }

  Future<void> delete(String filePath) async {
    final key = _keyFor(filePath);
    await _storage.delete(key: key);
    final keys = await _readIndex();
    keys.remove(key);
    await _writeIndex(keys);
  }

  /// Forget every remembered external-PDF password without touching any
  /// other secure value used by the app.
  Future<void> clearAll() async {
    final keys = await _readIndex();
    for (final key in keys) {
      await _storage.delete(key: key);
    }
    await _storage.delete(key: _indexKey);
  }

  String _keyFor(String filePath) {
    final normalizedPath = Uri.file(filePath).normalizePath().toString();
    final digest = SHA256Digest().process(utf8.encode(normalizedPath));
    final hash = base64UrlEncode(digest).replaceAll('=', '');
    return '$_keyPrefix$hash';
  }

  Future<List<String>> _readIndex() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet().toList();
      }
    } catch (_) {
      // A corrupt index must not prevent opening a PDF.
    }
    return <String>[];
  }

  Future<void> _writeIndex(List<String> keys) async {
    if (keys.isEmpty) {
      await _storage.delete(key: _indexKey);
      return;
    }
    await _storage.write(key: _indexKey, value: jsonEncode(keys));
  }
}
