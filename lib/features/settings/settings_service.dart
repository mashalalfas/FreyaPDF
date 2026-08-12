// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freya_pdf/features/settings/user_profile.dart';

/// Thin wrapper over SharedPreferences.
/// EncryptionProvider is single source of truth for passphrase —
/// passphrase is completely removed from this service.
class SettingsService {
  static const _prefix = 'mely_pdf_';

  // --- Keys ---
  static const _kThemeMode = '${_prefix}theme_mode'; // 'light'|'dark'|'system'
  static const _kAutoEncrypt = '${_prefix}auto_encrypt'; // bool
  static const _kUserProfile = '${_prefix}user_profile'; // JSON string
  static const _kLastDir = '${_prefix}last_dir'; // string (migrated from old key)
  static const _kLastReadPositions = '${_prefix}last_read'; // JSON map of path -> {page, total}
  static const _kFavorites = '${_prefix}favorites'; // JSON string list
  static const _kPageTurnMode = '${_prefix}page_turn_mode'; // bool
  static const _kDarkReadingMode = '${_prefix}dark_reading_mode'; // bool
  static const _kShowThumbnails = '${_prefix}show_thumbnails'; // bool
  static const _kAppLockEnabled = '${_prefix}app_lock_enabled'; // bool

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  // --- Theme ---
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) =>
      _prefs.setString(_kThemeMode, mode);

  // --- Auto-encrypt ---
  bool get autoEncrypt => _prefs.getBool(_kAutoEncrypt) ?? false;
  Future<void> setAutoEncrypt(bool value) =>
      _prefs.setBool(_kAutoEncrypt, value);

  // --- User profile ---
  UserProfile get userProfile {
    final raw = _prefs.getString(_kUserProfile);
    if (raw == null) return const UserProfile();
    return UserProfile.fromJson(jsonDecode(raw));
  }

  Future<void> setUserProfile(UserProfile profile) =>
      _prefs.setString(_kUserProfile, jsonEncode(profile.toJson()));

  // --- Last read positions (per file) ---
  Map<String, int> get lastReadPositions {
    final raw = _prefs.getString(_kLastReadPositions);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) {
        if (v is int) return MapEntry(k, v);
        if (v is Map) return MapEntry(k, (v['page'] as int?) ?? 0);
        return MapEntry(k, 0);
      });
    } catch (_) {
      return {};
    }
  }

  int? getLastReadPage(String path) {
    final raw = _prefs.getString(_kLastReadPositions);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final val = decoded[path];
      if (val is int) return val;
      if (val is Map) return val['page'] as int?;
      return null;
    } catch (_) {
      return null;
    }
  }

  ({int page, int totalPages})? getLastReadProgress(String path) {
    final raw = _prefs.getString(_kLastReadPositions);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final val = decoded[path];
      if (val is Map) {
        final page = val['page'] as int?;
        final total = val['total'] as int?;
        if (page != null && total != null) {
          return (page: page, totalPages: total);
        }
      }
      if (val is int) return (page: val, totalPages: 0);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastReadPage(String path, int page, int totalPages) async {
    final raw = _prefs.getString(_kLastReadPositions);
    Map<String, dynamic> all;
    if (raw != null) {
      try {
        all = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        all = {};
      }
    } else {
      all = {};
    }
    // Migrate old-format int values to new format on write
    for (final k in all.keys.toList()) {
      if (all[k] is int) {
        all[k] = {'page': all[k] as int, 'total': 0};
      }
    }
    all[path] = {'page': page, 'total': totalPages};
    await _prefs.setString(_kLastReadPositions, jsonEncode(all));
  }

  // --- Page-turn (horizontal swipe) mode ---
  bool get pageTurnMode => _prefs.getBool(_kPageTurnMode) ?? false;
  Future<void> setPageTurnMode(bool value) =>
      _prefs.setBool(_kPageTurnMode, value);

  // --- Dark reading mode ---
  bool get darkReadingMode => _prefs.getBool(_kDarkReadingMode) ?? false;
  Future<void> setDarkReadingMode(bool value) =>
      _prefs.setBool(_kDarkReadingMode, value);

  // --- Show thumbnails ---
  bool get showThumbnails => _prefs.getBool(_kShowThumbnails) ?? true;
  Future<void> setShowThumbnails(bool value) =>
      _prefs.setBool(_kShowThumbnails, value);

  // --- App lock ---
  bool get appLockEnabled => _prefs.getBool(_kAppLockEnabled) ?? false;
  Future<void> setAppLockEnabled(bool value) =>
      _prefs.setBool(_kAppLockEnabled, value);

  // --- Favorites ---
  Set<String> getFavorites() {
    final raw = _prefs.getStringList(_kFavorites);
    return raw?.toSet() ?? {};
  }

  Future<void> setFavorite(String path, bool value) async {
    final favorites = getFavorites();
    if (value) {
      favorites.add(path);
    } else {
      favorites.remove(path);
    }
    await _prefs.setStringList(_kFavorites, favorites.toList());
  }

  bool isFavorite(String path) => getFavorites().contains(path);

  // --- Migration from existing keys ---
  Future<void> migrateLegacyKeys() async {
    if (!_prefs.containsKey(_kLastDir)) {
      final oldDir = _prefs.getString('last_dir');
      if (oldDir != null) await _prefs.setString(_kLastDir, oldDir);
    }
  }
}
