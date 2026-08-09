import 'package:flutter/material.dart';
import 'package:freya_pdf/features/settings/user_profile.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';

/// Manages settings state: theme, auto-encrypt flag, user profile, last read positions.
class SettingsProvider extends ChangeNotifier {
  final SettingsService _service;

  SettingsProvider(this._service) {
    _init();
  }

  ThemeMode _themeMode = ThemeMode.system;
  bool _autoEncrypt = false;
  bool _continuousScroll = false;
  bool _darkReadingMode = false;
  bool _showThumbnails = true;
  bool _appLockEnabled = false;
  UserProfile _userProfile = const UserProfile();

  ThemeMode get themeMode => _themeMode;
  bool get autoEncrypt => _autoEncrypt;
  bool get continuousScroll => _continuousScroll;
  bool get darkReadingMode => _darkReadingMode;
  bool get showThumbnails => _showThumbnails;
  bool get appLockEnabled => _appLockEnabled;
  UserProfile get userProfile => _userProfile;

  int? getLastReadPage(String path) => _service.getLastReadPage(path);

  ({int page, int totalPages})? getLastReadProgress(String path) =>
      _service.getLastReadProgress(path);

  Future<void> setLastReadPage(String path, int page, {int totalPages = 0}) =>
      _service.setLastReadPage(path, page, totalPages);

  void _init() {
    _themeMode = _themeModeFromString(_service.themeMode);
    _autoEncrypt = _service.autoEncrypt;
    _continuousScroll = _service.continuousScroll;
    _darkReadingMode = _service.darkReadingMode;
    _showThumbnails = _service.showThumbnails;
    _appLockEnabled = _service.appLockEnabled;
    _userProfile = _service.userProfile;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _service.setThemeMode(_themeModeToString(mode));
    notifyListeners();
  }

  Future<void> setAutoEncrypt(bool value) async {
    _autoEncrypt = value;
    await _service.setAutoEncrypt(value);
    notifyListeners();
  }

  Future<void> setContinuousScroll(bool value) async {
    _continuousScroll = value;
    await _service.setContinuousScroll(value);
    notifyListeners();
  }

  Future<void> setDarkReadingMode(bool value) async {
    _darkReadingMode = value;
    await _service.setDarkReadingMode(value);
    notifyListeners();
  }

  Future<void> setShowThumbnails(bool value) async {
    _showThumbnails = value;
    await _service.setShowThumbnails(value);
    notifyListeners();
  }

  Future<void> setAppLockEnabled(bool value) async {
    _appLockEnabled = value;
    await _service.setAppLockEnabled(value);
    notifyListeners();
  }

  Future<void> updateUserProfile(UserProfile profile) async {
    _userProfile = profile;
    await _service.setUserProfile(profile);
    notifyListeners();
  }

  Future<void> reload() async {
    _init();
    notifyListeners();
  }

  // --- Helpers ---
  static ThemeMode _themeModeFromString(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
